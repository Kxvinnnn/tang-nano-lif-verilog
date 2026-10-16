#!/usr/bin/env python3
"""
train_and_export.py
Generador y cuantizador de pesos sinápticos para memoria BRAM (GW1NR-9C).
Mapeo físico: 0_hw = -70.0 mV, 1000_hw = -50.0 mV (20 uV / LSB).
Exporta a formato hexadecimal de 16 bits en complemento a dos para $readmemh.
"""

import os
import numpy as np

# Constantes electrofisiológicas y resolución hardware
V_REST_MV = -70.0
V_TH_MV   = -50.0
DELTA_V_MV = V_TH_MV - V_REST_MV  # 20.0 mV
HW_SCALE   = 1000.0               # 1000 unidades discretas = 20.0 mV
LSB_MV     = DELTA_V_MV / HW_SCALE # 0.020 mV/LSB (20 uV/LSB)

def float_to_twos_complement_hex(value_int16: int) -> str:
    """Convierte un entero con signo de 16 bits a representación hexadecimal en complemento a dos."""
    val_clamped = max(-32768, min(32767, int(value_int16)))
    return f"{val_clamped & 0xFFFF:04X}"

def generate_synaptic_weights():
    # Definiendo variaciones de potencial postsináptico biológico (EPSP e IPSP en mV)
    # Calibrados para la dinámica a 50 Hz con leak = V >>> 4
    # Direcciones pares: Pesos excitatorios (EPSP)
    # Direcciones impares: Pesos inhibitorios (IPSP)
    biological_epsp_ipsp_mv = [
        +1.36,  # [Addr 0] Excitatorio nominal  (+68 hw)
        -1.30,  # [Addr 1] Inhibitorio nominal (-65 hw)
        +1.36,  # [Addr 2] Excitatorio nominal  (+68 hw)
        -1.30,  # [Addr 3] Inhibitorio nominal (-65 hw)
        +1.40,  # [Addr 4] Excitatorio reforzado (+70 hw)
        -1.32,  # [Addr 5] Inhibitorio reforzado (-66 hw)
        +1.36,  # [Addr 6] Excitatorio nominal  (+68 hw)
        -1.30   # [Addr 7] Inhibitorio nominal (-65 hw)
    ]

    os.makedirs("data", exist_ok=True)
    hex_output_path = os.path.join("data", "pesos_sinapticos.hex")

    hex_lines = []
    print("=" * 68)
    print("  CUANTIZACIÓN LINEAL DE PESOS SINÁPTICOS (16-BIT TWO'S COMPLEMENT)")
    print(f"  Resolución: {LSB_MV*1e3:.1f} uV/LSB | Base Reposo: {V_REST_MV} mV | Umbral: {V_TH_MV} mV")
    print("=" * 68)
    print(f"{'ADDR':<6} | {'TIPO':<12} | {'BIOLÓGICO':<12} | {'INT16 HW':<10} | {'HEX ($readmemh)':<15}")
    print("-" * 68)

    for addr, v_bio in enumerate(biological_epsp_ipsp_mv):
        # Cuantización lineal directa: w_hw = round(v_bio / LSB_MV)
        w_hw = int(np.round(v_bio / LSB_MV))
        hex_val = float_to_twos_complement_hex(w_hw)
        hex_lines.append(hex_val)

        w_type = "EXCITATORIO" if v_bio > 0 else "INHIBITORIO"
        print(f"0x{addr:02X}   | {w_type:<12} | {v_bio:+6.2f} mV    | {w_hw:+6d}     | {hex_val}")

    with open(hex_output_path, "w", encoding="utf-8") as f:
        for line in hex_lines:
            f.write(line + "\n")

    print("-" * 68)
    print(f"[OK] Archivo generado exitosamente: {hex_output_path}")
    print(f"[OK] Total palabras de 16 bits exportadas: {len(hex_lines)}")
    print("=" * 68)

if __name__ == "__main__":
    generate_synaptic_weights()
