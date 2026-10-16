#!/usr/bin/env python3
"""
=============================================================================
lif_math_model.py - Modelo Matemático de Referencia de Neurona LIF (Golden Model)
=============================================================================
Modelo diferencial discreto en tiempo real idéntico al RTL (lif_neuron.v)
implementado en la FPGA Gowin GW1NR-9C (Tang Nano 9K).

Ecuaciones gobernantes en tiempo discreto (f_bio = 50 Hz, dt = 20 ms):
  1) Fuga (Leak simétrico hacia reposo V_REST = 0):
     - Si v_mem > 0: leak = max(1, v_mem >> 4)
     - Si v_mem < 0: leak = min(-1, v_mem >> 4)
     - Si v_mem == 0: leak = 0
  2) Integración diferencial:
     - v_next = max(V_MIN, v_mem - leak + i_syn)
  3) Disparo y Periodo Refractario:
     - Si refr_cnt > 0: refr_cnt -= 1, v_mem = 0, spike = 0
     - Si v_next >= V_TH: spike = 1, v_mem = 0, refr_cnt = REFRAC_TICKS
     - Si no: v_mem = v_next, spike = 0

Parámetros calibrados:
  - V_TH         = 1000
  - V_MIN        = -250 (límite de hiperpolarización)
  - REFRAC_TICKS = 16 ticks (320 ms a 50 Hz)
  - I_SYN_EXC    = +68 (disparo en ~0.76 s / 38 ticks)
  - I_SYN_INH    = -65 (hiperpolarización en ~0.24 s / 12 ticks)
=============================================================================
"""

import os
import sys
import argparse
from typing import List, Tuple, Dict, Any

# Configurar salida de texto segura en Windows
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


class LIFNeuron:
    """
    Emulador de precisión bit-accurate de la neurona LIF descrita en lif_neuron.v.
    """
    def __init__(self, v_th: int = 1000, v_min: int = -250, refrac_ticks: int = 16):
        self.v_th = int(v_th)
        self.v_min = int(v_min)
        self.refrac_ticks = int(refrac_ticks)

        self.v_mem = 0
        self.refr_cnt = 0
        self.spike = 0

    def reset(self):
        """Reinicia el estado interno a reposo."""
        self.v_mem = 0
        self.refr_cnt = 0
        self.spike = 0

    def compute_leak(self, v: int) -> int:
        """Cálculo de fuga idéntico a la lógica combinacional de lif_neuron.v."""
        if v > 0:
            shift = v >> 4
            return 1 if shift == 0 else shift
        elif v < 0:
            # En Verilog con signo (16'sd): v >>> 4 preserva el signo negativo
            # En Python: -1 >> 4 da -1 (aritmético)
            shift = v >> 4
            return -1 if shift == 0 else shift
        else:
            return 0

    def step(self, current_in: int) -> Tuple[int, int, int]:
        """
        Ejecuta un ciclo de bio_tick (dt = 20 ms).
        Retorna: (v_mem, spike, refr_cnt)
        """
        leak = self.compute_leak(self.v_mem)
        v_next = self.v_mem - leak + int(current_in)

        # Saturación inferior en el límite de hiperpolarización (-250)
        if v_next < self.v_min:
            v_next = self.v_min

        # Lógica secuencial (gobernada por bio_tick)
        self.spike = 0
        if self.refr_cnt > 0:
            self.refr_cnt -= 1
            self.v_mem = 0
        elif v_next >= self.v_th:
            self.spike = 1
            self.v_mem = 0
            self.refr_cnt = self.refrac_ticks
        else:
            self.v_mem = v_next

        return self.v_mem, self.spike, self.refr_cnt


def simulate_stimulus_sequence(current_sequence: List[int], 
                                dt_ms: float = 20.0) -> Dict[str, Any]:
    """
    Simula una serie temporal completa con el modelo LIF.
    """
    neuron = LIFNeuron(v_th=1000, v_min=-250, refrac_ticks=16)
    n_steps = len(current_sequence)

    time_ms = [i * dt_ms for i in range(n_steps)]
    v_mem_hist = []
    spike_hist = []
    refr_hist = []
    i_syn_hist = list(current_sequence)

    for i_syn in current_sequence:
        v, spk, refr = neuron.step(i_syn)
        v_mem_hist.append(v)
        spike_hist.append(spk)
        refr_hist.append(refr)

    return {
        "time_ms": time_ms,
        "current": i_syn_hist,
        "v_mem": v_mem_hist,
        "spike": spike_hist,
        "refr_cnt": refr_hist,
    }


def generate_standard_verification_sequence() -> List[int]:
    """
    Genera el vector de corriente idéntico al testbench RTL (tb_lif_neuron.v):
      - 38 ticks: Excitación continua (+68) -> Produce Spike en Tick 38
      - 16 ticks: Periodo refractario con excitación sostenida (+68)
      -  3 ticks: Reanudación de integración (+68)
      - 20 ticks: Inhibición continua (-65) -> Saturación en -250
      - 55 ticks: Relajación / Fuga natural hacia reposo (0)
    Total: 132 ticks (2640 ms de tiempo biológico simulado).
    """
    seq = []
    # Fase 1: Excitación hasta spike
    seq.extend([68] * 38)
    # Fase 2: Periodo refractario manteniendo +68
    seq.extend([68] * 16)
    # Fase 3: Reanudación post-refractario
    seq.extend([68] * 3)
    # Fase 4: Inhibición hacia V_MIN
    seq.extend([-65] * 20)
    # Fase 5: Fuga natural a reposo
    seq.extend([0] * 55)
    return seq


def compare_with_rtl_values(sim_results: Dict[str, Any]) -> bool:
    """
    Compara los puntos de control clave del modelo matemático con la simulación RTL.
    """
    v_mem = sim_results["v_mem"]
    spikes = sim_results["spike"]

    # Checkpoints esperados idénticos a tb_lif_neuron.v:
    # Índice 4 (Tick 5): 301
    # Índice 9 (Tick 10): 521
    # Índice 14 (Tick 15): 681
    # Índice 34 (Tick 35): 982
    # Índice 37 (Tick 38): Spike = 1, v_mem = 0
    # Índices 38..53 (Ticks 39..54): v_mem = 0 (16 ticks refractarios)
    # Índice 54 (Tick 55): v_mem = 68
    # Índice 56 (Tick 57): v_mem = 192
    # Índice 63 (Tick 64): v_mem = -250 (piso V_MIN)
    # Índice 131 (Tick 132): v_mem = 0 (reposo final)
    checkpoints = [
        (4, 301, "Tick 5 (+68)"),
        (9, 521, "Tick 10 (+68)"),
        (14, 681, "Tick 15 (+68)"),
        (34, 982, "Tick 35 (+68)"),
        (37, 0,   "Tick 38 (Disparo / Spike)", 1),
        (53, 0,   "Tick 54 (Fin Periodo Refractario)"),
        (54, 68,  "Tick 55 (Reanudación post-refractario)"),
        (56, 192, "Tick 57 (Post-refractario)"),
        (63, -250,"Tick 64 (Hiperpolarización V_MIN)"),
        (131, 0,  "Tick 132 (Reposo post-fuga)"),
    ]

    all_passed = True
    print("\n" + "=" * 76)
    print("  VERIFICACIÓN CRUZADA: MODELO MATEMÁTICO vs RTL (lif_neuron.v)")
    print("=" * 76)
    print(f"{'CHECKPOINT':<32} | {'V_MEM (PY)':>10} | {'SPIKE':>5} | {'ESTADO':<8}")
    print("-" * 76)

    for chk in checkpoints:
        idx = chk[0]
        expected_v = chk[1]
        desc = chk[2]
        expected_spk = chk[3] if len(chk) > 3 else 0

        actual_v = v_mem[idx]
        actual_spk = spikes[idx]

        ok_v = (actual_v == expected_v)
        ok_spk = (actual_spk == expected_spk)

        if ok_v and ok_spk:
            status = "[OK]"
        else:
            status = "[FAIL]"
            all_passed = False

        print(f"{desc:<32} | {actual_v:>10} | {actual_spk:>5} | {status:<8}")

    print("=" * 76)
    if all_passed:
        print("  >>> VALIDACIÓN EXITOSA: COINCIDENCIA 100% BIT-EXACTA CON RTL <<<")
    else:
        print("  >>> DISCREPANCIA DETECTADA ENTRE MODELO Y RTL <<<")
    print("=" * 76 + "\n")
    return all_passed


def plot_simulation(sim_results: Dict[str, Any], save_path: str = None):
    """
    Genera la figura de validación de tres paneles con Matplotlib.
    """
    try:
        import matplotlib
        matplotlib.use("Agg")  # Backend no interactivo seguro para scripts
        import matplotlib.pyplot as plt
    except ImportError:
        print("[WARN] matplotlib no está instalado. No se puede generar la gráfica.")
        return

    time_s = [t / 1000.0 for t in sim_results["time_ms"]]
    v_mem = sim_results["v_mem"]
    current = sim_results["current"]
    spikes = sim_results["spike"]
    refr = sim_results["refr_cnt"]

    fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(11, 8), sharex=True,
                                         gridspec_kw={'height_ratios': [3, 1.2, 1]})
    fig.patch.set_facecolor('#0d1117')

    for ax in (ax1, ax2, ax3):
        ax.set_facecolor('#161b22')
        ax.grid(True, linestyle='--', alpha=0.3, color='#8b949e')
        ax.tick_params(colors='#c9d1d9')
        for spine in ax.spines.values():
            spine.set_color('#30363d')

    # Panel 1: Potencial de Membrana
    ax1.plot(time_s, v_mem, color='#58a6ff', linewidth=2.0, label='Potencial de Membrana $V_{mem}$')
    ax1.axhline(1000, color='#f85149', linestyle='--', linewidth=1.5, label='Umbral de Disparo $V_{TH}=1000$')
    ax1.axhline(0, color='#8b949e', linestyle=':', linewidth=1.0, label='Potencial de Reposo $V_{REST}=0$')
    ax1.axhline(-250, color='#d29922', linestyle='--', linewidth=1.5, label='Límite Hiperpolarización $V_{MIN}=-250$')

    # Marcar Spikes con flechas / marcadores rojos
    spike_times = [time_s[i] for i, spk in enumerate(spikes) if spk == 1]
    if spike_times:
        ax1.scatter(spike_times, [1000] * len(spike_times), color='#ff4444', s=120, zorder=5, 
                    edgecolor='#ffffff', label='Spike Disparado (Acción Bioeléctrica)')

    ax1.set_ylabel('Potencial ($V_{mem}$)', color='#c9d1d9', fontsize=11, fontweight='bold')
    ax1.set_title('Modelo Matemático y Validación RTL: Neurona Leaky Integrate-and-Fire (LIF)', 
                  color='#f0f6fc', fontsize=13, fontweight='bold', pad=12)
    ax1.legend(loc='upper right', facecolor='#21262d', edgecolor='#30363d', labelcolor='#c9d1d9', fontsize=9)
    ax1.set_ylim(-300, 1150)

    # Panel 2: Corriente Sináptica
    ax2.step(time_s, current, where='post', color='#3fb950', linewidth=2.0, label='Corriente de Entrada $I_{syn}$')
    ax2.axhline(0, color='#8b949e', linestyle=':', linewidth=0.8)
    ax2.set_ylabel('Corriente ($I_{syn}$)', color='#c9d1d9', fontsize=10, fontweight='bold')
    ax2.legend(loc='upper right', facecolor='#21262d', edgecolor='#30363d', labelcolor='#c9d1d9', fontsize=9)
    ax2.set_ylim(-80, 85)

    # Panel 3: Contador Periodo Refractario
    ax3.step(time_s, refr, where='post', color='#bc8cff', linewidth=1.8, label='Ticks Refractarios Restantes')
    ax3.set_ylabel('Refractario', color='#c9d1d9', fontsize=10, fontweight='bold')
    ax3.set_xlabel('Tiempo Biológico (segundos)', color='#c9d1d9', fontsize=11, fontweight='bold')
    ax3.legend(loc='upper right', facecolor='#21262d', edgecolor='#30363d', labelcolor='#c9d1d9', fontsize=9)
    ax3.set_ylim(-1, 18)

    plt.tight_layout()

    if save_path:
        os.makedirs(os.path.dirname(os.path.abspath(save_path)), exist_ok=True)
        plt.savefig(save_path, dpi=200, facecolor=fig.get_facecolor(), edgecolor='none')
        print(f"[INFO] Gráfica de validación exportada exitosamente en: {save_path}")

    plt.close()


def export_csv(sim_results: Dict[str, Any], csv_path: str):
    """Exporta la serie temporal a CSV para análisis estadístico o en Excel."""
    os.makedirs(os.path.dirname(os.path.abspath(csv_path)), exist_ok=True)
    with open(csv_path, "w", encoding="utf-8") as f:
        f.write("tick,time_ms,i_syn,v_mem,spike,refr_cnt\n")
        n = len(sim_results["time_ms"])
        for i in range(n):
            f.write(f"{i+1},{sim_results['time_ms'][i]:.1f},{sim_results['current'][i]},"
                    f"{sim_results['v_mem'][i]},{sim_results['spike'][i]},{sim_results['refr_cnt'][i]}\n")
    print(f"[INFO] Datos tabulares exportados a: {csv_path}")


def main():
    parser = argparse.ArgumentParser(description="Modelo Matemático y Validador de Neurona LIF")
    parser.add_argument("--save-plot", type=str, default="docs/lif_validation_curve.png",
                        help="Ruta donde guardar la gráfica (por defecto: docs/lif_validation_curve.png)")
    parser.add_argument("--save-csv", type=str, default=None,
                        help="Ruta opcional para exportar los datos a CSV")
    parser.add_argument("--no-plot", action="store_true", help="Deshabilitar generación gráfica")
    args = parser.parse_args()

    print("============================================================================")
    print("  SIMULANDO MODELO MATEMÁTICO GOLDEN DE NEURONA LIF (50 Hz / 20 ms)")
    print("============================================================================")

    stimulus = generate_standard_verification_sequence()
    results = simulate_stimulus_sequence(stimulus)

    passed = compare_with_rtl_values(results)

    if args.save_csv:
        export_csv(results, args.save_csv)

    if not args.no_plot and args.save_plot:
        plot_simulation(results, save_path=args.save_plot)

    if passed:
        print("[RESULTADO] Verificación matemática superada con éxito.")
        sys.exit(0)
    else:
        print("[RESULTADO] Verificación falló en uno o más puntos.")
        sys.exit(1)


if __name__ == "__main__":
    main()
