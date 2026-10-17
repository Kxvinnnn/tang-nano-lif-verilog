import serial
import time
import argparse
import sys
import serial.tools.list_ports

def parse_args():
    parser = argparse.ArgumentParser(description="Neuromorphic SNN UART Telemetry Listener")
    parser.add_argument("--port", type=str, default=None, help="Serial port (e.g., COM4 or /dev/ttyUSB0)")
    parser.add_argument("--baudrate", type=int, default=115200, help="Baud rate (default: 115200)")
    return parser.parse_args()

def select_port_interactive():
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("[WARN] No connected serial ports detected.")
        return None
    print("[INFO] Available serial ports:")
    for idx, p in enumerate(ports):
        print(f"  [{idx}] {p.device} - {p.description}")
    
    choice = input("Select port index (or press Enter for standalone simulator): ")
    if choice.strip() == "":
        return None
    try:
        idx = int(choice)
        return ports[idx].device
    except Exception:
        print("[ERROR] Invalid port selection.")
        return None

def run_neuromorphic_demo():
    args = parse_args()
    port = args.port
    baudrate = args.baudrate

    if port is None:
        port = select_port_interactive()

    print(f"[INFO] Initializing telemetry on port: {port} at {baudrate} baud...")
    
    ser = None
    if port:
        try:
            ser = serial.Serial(port, baudrate, timeout=0.1)
            print(f"[INFO] Connection successfully established on {port}.")
        except Exception as e:
            print(f"[WARN] Failed to open {port} ({e}). Falling back to autonomous simulator mode.")

    if ser is None:
        print("[SIMULATOR] Running live software simulation of LIF neuron...")
        for i in range(10):
            v_mem = min(1000, i * 120)
            spike = 1 if v_mem >= 1000 else 0
            print(f"[SIMULATOR] V_mem: {v_mem} mV | Spike: {spike} | LEDs: {bin(v_mem >> 7)}")
            time.sleep(0.4)
        print("[PASSED] Demonstration completed in simulator mode.")
        return

    while True:
        try:
            byte = ser.read(1)
            if byte == b'\xaa':
                packet = ser.read(3)
                if len(packet) == 3:
                    v_mem = (packet[0] << 8) | packet[1]
                    flags = packet[2]
                    print(f"[UART DATA] V_mem: {v_mem} mV | Flags: {bin(flags)}")
        except KeyboardInterrupt:
            print("[INFO] Telemetry streaming halted by user.")
            break
    ser.close()

if __name__ == '__main__':
    run_neuromorphic_demo()
