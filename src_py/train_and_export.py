#!/usr/bin/env python3
"""
=============================================================================
train_and_export.py - Synaptic Weight Generator and Quantizer for BSRAM
Target FPGA: Gowin GW1NR-9C (Tang Nano 9K)
=============================================================================
Physical Electrophysiological Mapping:
  - Resting potential: 0_hw = -70.0 mV
  - Action potential threshold: 1000_hw = -50.0 mV
  - Resolution: 20 uV / LSB (0.020 mV/LSB)
Exports 16-bit signed two's complement hexadecimal coefficients for Verilog $readmemh.
=============================================================================
"""

import os
import numpy as np

# Electrophysiological constants and hardware scaling
V_REST_MV = -70.0
V_TH_MV   = -50.0
DELTA_V_MV = V_TH_MV - V_REST_MV  # 20.0 mV
HW_SCALE   = 1000.0               # 1000 discrete integer units = 20.0 mV
LSB_MV     = DELTA_V_MV / HW_SCALE # 0.020 mV/LSB (20 uV/LSB)


def float_to_twos_complement_hex(value_int16: int) -> str:
    """Converts a 16-bit signed integer to two's complement 4-character hex."""
    val_clamped = max(-32768, min(32767, int(value_int16)))
    return f"{val_clamped & 0xFFFF:04X}"


def generate_synaptic_weights():
    # Calibrated post-synaptic biological potentials (EPSP and IPSP in mV)
    # Tuned for 50 Hz discrete Euler dynamics with leak = V >>> 4
    # Even addresses: Excitatory weights (EPSP)
    # Odd addresses:  Inhibitory weights (IPSP)
    biological_epsp_ipsp_mv = [
        +1.36,  # [Addr 0] Nominal Excitatory  (+68 hw)
        -1.30,  # [Addr 1] Nominal Inhibitory  (-65 hw)
        +1.36,  # [Addr 2] Nominal Excitatory  (+68 hw)
        -1.30,  # [Addr 3] Nominal Inhibitory  (-65 hw)
        +1.40,  # [Addr 4] Boosted Excitatory  (+70 hw)
        -1.32,  # [Addr 5] Boosted Inhibitory  (-66 hw)
        +1.36,  # [Addr 6] Nominal Excitatory  (+68 hw)
        -1.30   # [Addr 7] Nominal Inhibitory  (-65 hw)
    ]

    os.makedirs("data", exist_ok=True)
    hex_output_primary = os.path.join("data", "synaptic_weights.hex")
    hex_output_legacy = os.path.join("data", "pesos_sinapticos.hex")

    hex_lines = []
    print("=" * 72)
    print("  LINEAR QUANTIZATION OF SYNAPTIC WEIGHTS (16-BIT TWO'S COMPLEMENT)")
    print(f"  Resolution: {LSB_MV*1e3:.1f} uV/LSB | Rest Baseline: {V_REST_MV} mV | Threshold: {V_TH_MV} mV")
    print("=" * 72)
    print(f"{'ADDR':<6} | {'TYPE':<12} | {'BIOLOGICAL':<14} | {'INT16 HW':<10} | {'HEX ($readmemh)':<15}")
    print("-" * 72)

    for addr, v_bio in enumerate(biological_epsp_ipsp_mv):
        w_hw = int(np.round(v_bio / LSB_MV))
        hex_val = float_to_twos_complement_hex(w_hw)
        hex_lines.append(hex_val)

        w_type = "EXCITATORY" if v_bio > 0 else "INHIBITORY"
        print(f"0x{addr:02X}   | {w_type:<12} | {v_bio:+6.2f} mV      | {w_hw:+6d}     | {hex_val}")

    for out_path in (hex_output_primary, hex_output_legacy):
        with open(out_path, "w", encoding="utf-8") as f:
            for line in hex_lines:
                f.write(line + "\n")

    print("-" * 72)
    print(f"[OK] Primary HEX file generated: {hex_output_primary}")
    print(f"[OK] Legacy HEX file mirrored:   {hex_output_legacy}")
    print(f"[OK] Total 16-bit synaptic words exported: {len(hex_lines)}")
    print("=" * 72)


if __name__ == "__main__":
    generate_synaptic_weights()
