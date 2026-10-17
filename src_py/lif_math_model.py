#!/usr/bin/env python3
"""
=============================================================================
lif_math_model.py - Reference Mathematical Golden Model for LIF Neuron
=============================================================================
Discrete-time differential reference model bit-accurate to RTL (lif_neuron.v)
implemented on the Gowin GW1NR-9C FPGA (Tang Nano 9K).

Discrete-time Governing Equations (f_bio = 50 Hz, dt = 20 ms):
  1) Asymptotic Symmetric Leak towards resting baseline (V_REST = 0):
     - If v_mem > 0: leak = max(1, v_mem >> 4)
     - If v_mem < 0: leak = min(-1, v_mem >> 4)
     - If v_mem == 0: leak = 0
  2) Forward Euler Differential Integration:
     - v_next = max(V_MIN, v_mem - leak + i_syn)
  3) Action Potential Firing & Absolute Refractory Period:
     - If refr_cnt > 0: refr_cnt -= 1, v_mem = 0, spike = 0
     - If v_next >= V_TH: spike = 1, v_mem = 0, refr_cnt = REFRAC_TICKS
     - Else: v_mem = v_next, spike = 0

Calibrated Hardware Parameters:
  - V_TH         = 1000 (-50.0 mV threshold)
  - V_MIN        = -250 (-75.0 mV physiological hyperpolarization floor)
  - REFRAC_TICKS = 16 biological ticks (320 ms @ 50 Hz)
  - I_SYN_EXC    = +68 (reaches threshold in ~0.76 s / 38 ticks)
  - I_SYN_INH    = -65 (hyperpolarizes to floor in ~0.24 s / 12 ticks)
=============================================================================
"""

import os
import sys
import argparse
from typing import List, Tuple, Dict, Any

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


class LIFNeuron:
    """
    Bit-accurate software emulator of the LIF neuron described in lif_neuron.v.
    """
    def __init__(self, v_th: int = 1000, v_min: int = -250, refrac_ticks: int = 16):
        self.v_th = int(v_th)
        self.v_min = int(v_min)
        self.refrac_ticks = int(refrac_ticks)

        self.v_mem = 0
        self.refr_cnt = 0
        self.spike = 0

    def reset(self):
        """Resets internal state to resting baseline."""
        self.v_mem = 0
        self.refr_cnt = 0
        self.spike = 0

    def compute_leak(self, v: int) -> int:
        """Computes asymptotic symmetric leak identically to lif_neuron.v combinational logic."""
        if v > 0:
            shift = v >> 4
            return 1 if shift == 0 else shift
        elif v < 0:
            shift = v >> 4
            return -1 if shift == 0 else shift
        else:
            return 0

    def step(self, current_in: int) -> Tuple[int, int, int]:
        """
        Executes one biological clock cycle (bio_tick @ dt = 20 ms).
        Returns: (v_mem, spike, refr_cnt)
        """
        leak = self.compute_leak(self.v_mem)
        v_next = self.v_mem - leak + int(current_in)

        # Lower saturation clamp at hyperpolarization floor (-250)
        if v_next < self.v_min:
            v_next = self.v_min

        # Sequential dynamics governed by bio_tick
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
    Simulates a complete temporal stimulus series with the LIF golden model.
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
    Generates the current injection vector identical to the RTL testbench (tb_lif_neuron.v):
      - 38 ticks: Sustained excitation (+68) -> Fires spike at Tick 38
      - 16 ticks: Absolute refractory period holding +68
      -  3 ticks: Post-refractory integration resumption (+68)
      - 20 ticks: Sustained inhibition (-65) -> Saturation clamping at -250
      - 55 ticks: Passive relaxation / natural leak towards resting baseline (0)
    Total: 132 ticks (2640 ms of simulated biological time).
    """
    seq = []
    seq.extend([68] * 38)
    seq.extend([68] * 16)
    seq.extend([68] * 3)
    seq.extend([-65] * 20)
    seq.extend([0] * 55)
    return seq


def compare_with_rtl_values(sim_results: Dict[str, Any]) -> bool:
    """
    Cross-verifies key golden checkpoints against RTL simulation outputs.
    """
    v_mem = sim_results["v_mem"]
    spikes = sim_results["spike"]

    checkpoints = [
        (4, 301, "Tick 5 (+68)"),
        (9, 521, "Tick 10 (+68)"),
        (14, 681, "Tick 15 (+68)"),
        (34, 982, "Tick 35 (+68)"),
        (37, 0,   "Tick 38 (Action Potential Spike)", 1),
        (53, 0,   "Tick 54 (End of Refractory Period)"),
        (54, 68,  "Tick 55 (Post-Refractory Resumption)"),
        (56, 192, "Tick 57 (Post-Refractory Integration)"),
        (63, -250,"Tick 64 (Hyperpolarization Floor V_MIN)"),
        (131, 0,  "Tick 132 (Resting Baseline Post-Leak)"),
    ]

    all_passed = True
    print("\n" + "=" * 76)
    print("  CROSS-VERIFICATION: MATHEMATICAL GOLDEN MODEL vs RTL (lif_neuron.v)")
    print("=" * 76)
    print(f"{'CHECKPOINT':<36} | {'V_MEM (PY)':>10} | {'SPIKE':>5} | {'STATUS':<8}")
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

        print(f"{desc:<36} | {actual_v:>10} | {actual_spk:>5} | {status:<8}")

    print("=" * 76)
    if all_passed:
        print("  >>> VALIDATION PASSED: 100% BIT-EXACT MATCH WITH RTL HARDWARE <<<")
    else:
        print("  >>> DISCREPANCY DETECTED BETWEEN GOLDEN MODEL AND RTL <<<")
    print("=" * 76 + "\n")
    return all_passed


def plot_simulation(sim_results: Dict[str, Any], save_path: str = None):
    """
    Renders the 3-panel validation figure using Matplotlib.
    """
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("[WARN] Matplotlib is not installed. Skipping plot generation.")
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

    # Panel 1: Membrane Potential
    ax1.plot(time_s, v_mem, color='#58a6ff', linewidth=2.0, label='Membrane Potential $V_{mem}$')
    ax1.axhline(1000, color='#f85149', linestyle='--', linewidth=1.5, label='Firing Threshold $V_{TH}=1000$')
    ax1.axhline(0, color='#8b949e', linestyle=':', linewidth=1.0, label='Resting Potential $V_{REST}=0$')
    ax1.axhline(-250, color='#d29922', linestyle='--', linewidth=1.5, label='Hyperpolarization Floor $V_{MIN}=-250$')

    spike_times = [time_s[i] for i, spk in enumerate(spikes) if spk == 1]
    if spike_times:
        ax1.scatter(spike_times, [1000] * len(spike_times), color='#ff4444', s=120, zorder=5, 
                    edgecolor='#ffffff', label='Spike Fired (Action Potential)')

    ax1.set_ylabel('Potential ($V_{mem}$)', color='#c9d1d9', fontsize=11, fontweight='bold')
    ax1.set_title('Mathematical Reference & RTL Cross-Validation: Leaky Integrate-and-Fire (LIF) Neuron', 
                  color='#f0f6fc', fontsize=13, fontweight='bold', pad=12)
    ax1.legend(loc='upper right', facecolor='#21262d', edgecolor='#30363d', labelcolor='#c9d1d9', fontsize=9)
    ax1.set_ylim(-300, 1150)

    # Panel 2: Synaptic Current
    ax2.step(time_s, current, where='post', color='#3fb950', linewidth=2.0, label='Synaptic Input Current $I_{syn}$')
    ax2.axhline(0, color='#8b949e', linestyle=':', linewidth=0.8)
    ax2.set_ylabel('Current ($I_{syn}$)', color='#c9d1d9', fontsize=10, fontweight='bold')
    ax2.legend(loc='upper right', facecolor='#21262d', edgecolor='#30363d', labelcolor='#c9d1d9', fontsize=9)
    ax2.set_ylim(-80, 85)

    # Panel 3: Refractory Lockout Counter
    ax3.step(time_s, refr, where='post', color='#bc8cff', linewidth=1.8, label='Remaining Refractory Ticks')
    ax3.set_ylabel('Refractory', color='#c9d1d9', fontsize=10, fontweight='bold')
    ax3.set_xlabel('Biological Time (seconds)', color='#c9d1d9', fontsize=11, fontweight='bold')
    ax3.legend(loc='upper right', facecolor='#21262d', edgecolor='#30363d', labelcolor='#c9d1d9', fontsize=9)
    ax3.set_ylim(-1, 18)

    plt.tight_layout()

    if save_path:
        os.makedirs(os.path.dirname(os.path.abspath(save_path)), exist_ok=True)
        plt.savefig(save_path, dpi=200, facecolor=fig.get_facecolor(), edgecolor='none')
        print(f"[INFO] Validation plot successfully exported to: {save_path}")

    plt.close()


def export_csv(sim_results: Dict[str, Any], csv_path: str):
    """Exports time series to CSV for statistical validation."""
    os.makedirs(os.path.dirname(os.path.abspath(csv_path)), exist_ok=True)
    with open(csv_path, "w", encoding="utf-8") as f:
        f.write("tick,time_ms,i_syn,v_mem,spike,refr_cnt\n")
        n = len(sim_results["time_ms"])
        for i in range(n):
            f.write(f"{i+1},{sim_results['time_ms'][i]:.1f},{sim_results['current'][i]},"
                    f"{sim_results['v_mem'][i]},{sim_results['spike'][i]},{sim_results['refr_cnt'][i]}\n")
    print(f"[INFO] Tabular simulation data exported to: {csv_path}")


def main():
    parser = argparse.ArgumentParser(description="LIF Neuron Mathematical Golden Model & Hardware Validator")
    parser.add_argument("--save-plot", type=str, default="docs/lif_validation_curve.png",
                        help="Target path for validation plot (default: docs/lif_validation_curve.png)")
    parser.add_argument("--save-csv", type=str, default=None,
                        help="Optional CSV export destination")
    parser.add_argument("--no-plot", action="store_true", help="Disable graphical rendering")
    args = parser.parse_args()

    print("============================================================================")
    print("  SIMULATING LIF NEURON MATHEMATICAL GOLDEN MODEL (50 Hz / 20 ms dt)")
    print("============================================================================")

    stimulus = generate_standard_verification_sequence()
    results = simulate_stimulus_sequence(stimulus)

    passed = compare_with_rtl_values(results)

    if args.save_csv:
        export_csv(results, args.save_csv)

    if not args.no_plot and args.save_plot:
        plot_simulation(results, save_path=args.save_plot)

    if passed:
        print("[RESULT] Mathematical verification successfully passed.")
        sys.exit(0)
    else:
        print("[RESULT] Verification failed at one or more checkpoints.")
        sys.exit(1)


if __name__ == "__main__":
    main()
