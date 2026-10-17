#!/usr/bin/env python3
"""
=============================================================================
telemetry_listener.py - Real-Time Neuromorphic LIF Telemetry Acquisition Host
Platform: Tang Nano 9K FPGA (Gowin GW1NR-9C) over USB-UART Bridge @ 115200 bps
=============================================================================
Architecture:
  - High-Priority Daemon Thread: Drains OS serial FIFO continuously,
    synchronizes to 9-byte binary packet boundaries [0xAA, 0x55, ... 0x0A],
    and performs strict XOR payload parity validation.
  - Thread-Safe Bounded Queue (queue.Queue): Decouples UART streaming from
    GUI/Matplotlib rendering latencies to prevent packet drop and buffer overrun.
  - Dual Consumer Modes:
      1. Dynamic Real-Time Matplotlib Oscilloscope (Interactive GUI)
      2. Fast Lightweight ASCII Terminal Oscilloscope with CSV logging
=============================================================================
"""

import sys
import time
import struct
import argparse
import threading
import queue
from collections import deque

# Configure UTF-8 stdout on Windows hosts
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

try:
    import serial
except ImportError:
    print("[ERROR] 'pyserial' package is not installed. Install with: pip install pyserial")
    sys.exit(1)

# Physical UART Telemetry Protocol Constants (9-Byte Packet @ 50 Hz / 20 ms)
SYNC_BYTE1 = 0xAA
SYNC_BYTE2 = 0x55
PACKET_LEN = 9  # [0xAA, 0x55, v_h, v_l, i_h, i_l, spike, xor_chk, 0x0A]


def parse_packet(raw_bytes):
    """
    Decodes a 9-byte structured binary telemetry packet.
    Returns (v_mem, i_syn, spike) tuple or None if delimiters or XOR parity check fail.
    """
    try:
        if len(raw_bytes) != PACKET_LEN:
            return None
        if raw_bytes[0] != SYNC_BYTE1 or raw_bytes[1] != SYNC_BYTE2:
            return None
        if raw_bytes[8] != 0x0A:
            return None

        v_h = raw_bytes[2]
        v_l = raw_bytes[3]
        i_h = raw_bytes[4]
        i_l = raw_bytes[5]
        spike_raw = raw_bytes[6]
        chk = raw_bytes[7]

        # Strict XOR checksum verification across 5 payload bytes
        expected_chk = v_h ^ v_l ^ i_h ^ i_l ^ spike_raw
        if chk != expected_chk:
            return None

        v_mem = struct.unpack('>h', bytes([v_h, v_l]))[0]
        i_syn = struct.unpack('>h', bytes([i_h, i_l]))[0]
        spike = bool(spike_raw & 0x01)

        return v_mem, i_syn, spike
    except Exception:
        return None


def uart_producer_thread(ser, data_queue, stop_event, log_file=None):
    """
    Dedicated producer thread (daemon=True).
    Continuously drains the OS serial buffer at 115200 bps, executes the packet
    synchronizer FSM, and enqueues verified samples into data_queue.
    """
    csv_handle = None
    if log_file:
        try:
            csv_handle = open(log_file, "w", encoding="utf-8")
            csv_handle.write("step,time_ms,time_s,i_syn,v_mem,spike\n")
            csv_handle.flush()
        except Exception as e:
            print(f"[WARNING] Could not initialize CSV log: {e}")

    sync_state = 0
    buffer = bytearray()
    sample_cnt = 0

    try:
        while not stop_event.is_set():
            in_waiting = ser.in_waiting
            bytes_to_read = in_waiting if in_waiting > 0 else 1
            raw_chunk = ser.read(bytes_to_read)
            if not raw_chunk:
                continue

            for val in raw_chunk:
                if sync_state == 0:
                    if val == SYNC_BYTE1:
                        sync_state = 1
                        buffer = bytearray([val])
                elif sync_state == 1:
                    if val == SYNC_BYTE2:
                        sync_state = 2
                        buffer.append(val)
                    else:
                        sync_state = 0
                elif sync_state == 2:
                    buffer.append(val)
                    if len(buffer) == PACKET_LEN:
                        parsed = parse_packet(buffer)
                        if parsed is not None:
                            v_mem, i_syn, spike = parsed
                            sample_cnt += 1
                            t_ms = sample_cnt * 20.0
                            t_s = t_ms / 1000.0

                            if csv_handle:
                                spk_int = 1 if spike else 0
                                csv_handle.write(f"{sample_cnt},{t_ms:.1f},{t_s:.3f},{i_syn},{v_mem},{spk_int}\n")
                                csv_handle.flush()

                            try:
                                data_queue.put_nowait((sample_cnt, v_mem, i_syn, spike, t_ms, t_s))
                            except queue.Full:
                                try:
                                    data_queue.get_nowait()
                                    data_queue.put_nowait((sample_cnt, v_mem, i_syn, spike, t_ms, t_s))
                                except Exception:
                                    pass

                        sync_state = 0
    except Exception as e:
        if not stop_event.is_set():
            print(f"\n[UART THREAD ERROR] Serial acquisition exception: {e}")
    finally:
        if csv_handle:
            csv_handle.close()


def run_console_mode(data_queue, stop_event, log_file=None):
    """Consumer terminal mode with live ASCII oscilloscope."""
    print("=" * 75)
    print("  LIVE NEUROMORPHIC TELEMETRY (CONSOLE MODE) - Tang Nano 9K FPGA")
    print("  Baud Rate: 115200 | Sample Rate: 50 Hz | Producer-Consumer Architecture")
    if log_file:
        print(f"  Active CSV Logging -> {log_file}")
    print("=" * 75)
    print(f"{'V_MEM':>7} | {'I_SYN':>7} | {'STATUS':<15} | {'MEMBRANE BAR (-250 to 1000)':<30}")
    print("-" * 75)

    try:
        while not stop_event.is_set():
            try:
                sample_cnt, v_mem, i_syn, spike, t_ms, t_s = data_queue.get(timeout=0.1)
            except queue.Empty:
                continue

            if spike:
                status = "[* SPIKE! *]"
            elif i_syn > 0:
                status = "[EXCITING]"
            elif i_syn < 0:
                status = "[INHIBITING]"
            else:
                status = "[REST/LEAK]"

            norm_pos = int((v_mem + 250) / 1250 * 25)
            norm_pos = max(0, min(25, norm_pos))
            bar = [" "] * 26
            bar[5] = "|"  # Resting level mark (v=0 -> index 5)
            for i in range(min(5, norm_pos), max(5, norm_pos) + 1):
                bar[i] = "#"
            if spike:
                bar[25] = "*"
            bar_str = "[" + "".join(bar) + "]"

            sys.stdout.write(f"\r{v_mem:7d} | {i_syn:7d} | {status:<15} | {bar_str:<28}")
            sys.stdout.flush()
    except KeyboardInterrupt:
        print("\n[INFO] Stopped by user.")
        stop_event.set()


def run_gui_mode(data_queue, stop_event, log_file=None):
    """Dynamic graphical consumer mode using Matplotlib."""
    try:
        import matplotlib.pyplot as plt
        import matplotlib.animation as animation
    except ImportError:
        print("[WARNING] Matplotlib not available, switching to terminal console mode...")
        run_console_mode(data_queue, stop_event, log_file=log_file)
        return

    WINDOW_SIZE = 150  # 3 seconds @ 50 Hz
    t_data = deque(maxlen=WINDOW_SIZE)
    v_data = deque(maxlen=WINDOW_SIZE)
    i_data = deque(maxlen=WINDOW_SIZE)
    spike_x = deque(maxlen=WINDOW_SIZE)
    spike_y = deque(maxlen=WINDOW_SIZE)

    fig, (ax_v, ax_i) = plt.subplots(2, 1, figsize=(10, 6), sharex=True,
                                     gridspec_kw={'height_ratios': [3, 1]})
    fig.canvas.manager.set_window_title("Real-Time Neuromorphic LIF Telemetry - Tang Nano 9K FPGA")

    # Membrane Potential Subplot
    ax_v.set_ylabel("Membrane Potential V_mem", fontsize=11, fontweight='bold')
    ax_v.set_ylim(-300, 1150)
    line_v, = ax_v.plot([], [], color='#00E5FF', lw=2, label="V_mem (Membrane Potential)")
    scatter_spikes, = ax_v.plot([], [], 'r*', markersize=14, label="Action Potential Spike (1000)")

    # Electrophysiological Reference Levels
    ax_v.axhline(1000, color='#FF1744', linestyle='--', lw=1.5, label="Threshold V_TH (1000)")
    ax_v.axhline(0, color='#78909C', linestyle=':', lw=1.2, label="Resting Potential V_rest (0)")
    ax_v.axhline(-250, color='#651FFF', linestyle='--', lw=1.2, label="Hyperpolarization Floor V_MIN (-250)")

    # Hardware LED Voltmeter Activation Thresholds
    for thr, l_name in [(220, "LED 0"), (440, "LED 1"), (640, "LED 2"), (800, "LED 3"), (920, "LED 4")]:
        ax_v.axhline(thr, color='#455A64', linestyle='-', alpha=0.3, lw=0.8)
        ax_v.text(0, thr + 10, f" {l_name} ({thr})", color='#90A4AE', fontsize=8)

    ax_v.legend(loc="upper left", framealpha=0.85, fontsize=9)
    ax_v.grid(True, linestyle=":", alpha=0.6)

    # Synaptic Current Subplot
    ax_i.set_ylabel("I_syn (BSRAM)", fontsize=11, fontweight='bold')
    ax_i.set_xlabel("Recent Samples (50 Hz / 20 ms dt)", fontsize=11)
    ax_i.set_ylim(-100, 100)
    line_i, = ax_i.plot([], [], color='#FFD600', lw=1.8, label="I_syn (Synaptic Current)")
    ax_i.axhline(0, color='#78909C', linestyle=':', lw=1.0)
    ax_i.legend(loc="upper left", framealpha=0.85, fontsize=9)
    ax_i.grid(True, linestyle=":", alpha=0.6)

    plt.tight_layout()

    def update(frame):
        updated = False
        while not data_queue.empty():
            try:
                sample_cnt, v_mem, i_syn, spike, t_ms, t_s = data_queue.get_nowait()
                t_data.append(sample_cnt)
                v_data.append(v_mem)
                i_data.append(i_syn)
                if spike:
                    spike_x.append(sample_cnt)
                    spike_y.append(1000)
                updated = True
            except queue.Empty:
                break

        if updated and len(t_data) > 0:
            line_v.set_data(t_data, v_data)
            line_i.set_data(t_data, i_data)
            scatter_spikes.set_data(spike_x, spike_y)
            ax_v.set_xlim(min(t_data), max(t_data) + 5)

        return line_v, line_i, scatter_spikes

    try:
        ani = animation.FuncAnimation(fig, update, interval=20, blit=False)
        plt.show()
    finally:
        stop_event.set()


def main():
    parser = argparse.ArgumentParser(description="Real-Time LIF Neuromorphic Telemetry Monitor (Threaded).")
    parser.add_argument("--port", default="COM4", help="Serial port identifier (default: COM4)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--console", action="store_true", help="Force lightweight terminal console mode")
    parser.add_argument("--log-csv", default=None, help="Output CSV path for continuous telemetry logging")
    args = parser.parse_args()

    print(f"[INFO] Connecting to {args.port} @ {args.baud} baud...")
    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.1)
        ser.reset_input_buffer()
        print(f"[OK] Successfully connected to {args.port}.")
    except Exception as e:
        print(f"[ERROR] Could not open {args.port}: {e}")
        print("[TIP] Ensure the USB-C cable is connected and no other tool is locking the COM port.")
        sys.exit(1)

    data_queue = queue.Queue(maxsize=1000)
    stop_event = threading.Event()

    producer = threading.Thread(
        target=uart_producer_thread,
        args=(ser, data_queue, stop_event, args.log_csv),
        daemon=True,
        name="UART-Producer-Thread"
    )
    producer.start()
    print("[OK] Telemetry producer thread running (daemon=True). Thread decoupling active.")

    try:
        if args.console:
            run_console_mode(data_queue, stop_event, log_file=args.log_csv)
        else:
            run_gui_mode(data_queue, stop_event, log_file=args.log_csv)
    finally:
        stop_event.set()
        producer.join(timeout=0.5)
        ser.close()
        print(f"[INFO] Serial port {args.port} closed cleanly.")


if __name__ == "__main__":
    main()
