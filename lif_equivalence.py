#!/usr/bin/env python3
"""
=============================================================================
lif_equivalence.py - Modelo de Equivalencia Hardware LIF en Punto Fijo (16-bit)
=============================================================================
Rol: Científico de Datos Computacional / Ingeniero Neuromórfico
Descripción:
  Emulación ciclo a ciclo de hardware digital (FPGA Tang Nano 9K / GW1NR-9C)
  para una neurona Leaky Integrate-and-Fire (LIF) en punto fijo con signo de 16 bits.

Ecuación en tiempo discreto a 50 Hz (dt = 20 ms, reloj biológico):
  V(t+1) = V(t) - (V(t) >> 4) + I_syn

Reglas de disparo y refractariedad:
  - Si V(t) > 1000 (V_TH):
      * Spike = 1
      * V(t)  = -250 (Hiperpolarización post-disparo / AHP)
      * Periodo refractario = 16 ticks (320 ms a 50 Hz)
  - Durante el periodo refractario (16 ticks):
      * El potencial se mantiene bloqueado en -250 y se ignoran estímulos sinápticos.

Salidas:
  - Simulación de 1000 pasos de tiempo (20 segundos biológicos continuos).
  - Visualización gráfica de alta resolución (Matplotlib).
  - Exportación de telemetría a CSV para correlación directa con UART FPGA (COM4).
=============================================================================
"""

import os
import sys
import argparse
import numpy as np
import matplotlib
matplotlib.use("Agg")  # Backend no interactivo seguro para scripts/CLI
import matplotlib.pyplot as plt

# Configuración de codificación segura para consola Windows
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


class FixedPointLIFNeuron:
    """
    Modelo de precisión de ciclo y de bit para neurona LIF en punto fijo (int16).
    Emula fielmente los registros y sumadores de dos complementos de hardware.
    """
    def __init__(self, v_th: int = 1000, v_reset: int = -250, refrac_ticks: int = 16):
        self.v_th = np.int16(v_th)
        self.v_reset = np.int16(v_reset)
        self.refrac_ticks = int(refrac_ticks)

        self.v_mem = np.int16(0)
        self.refr_cnt = int(0)
        self.spike = np.uint8(0)

    def reset(self):
        """Reinicia la neurona al estado de reposo."""
        self.v_mem = np.int16(0)
        self.refr_cnt = int(0)
        self.spike = np.uint8(0)

    def step(self, i_syn: int) -> tuple[np.int16, np.uint8, int]:
        """
        Ejecuta exactamente un ciclo biológico a 50 Hz (dt = 20 ms).
        Aritmética en enteros con signo de 16 bits (np.int16).
        """
        i_val = np.int16(i_syn)
        self.spike = np.uint8(0)

        # 1. Comprobación del periodo refractario activo
        if self.refr_cnt > 0:
            self.refr_cnt -= 1
            self.v_mem = self.v_reset
            return self.v_mem, self.spike, self.refr_cnt

        # 2. Desplazamiento aritmético con signo de 4 posiciones (V >> 4)
        #    En int16 con signo, np.right_shift preserva el bit de signo
        v_current = int(self.v_mem)
        leak = v_current >> 4

        # Compensación de convergencia a reposo (evita atascos por truncamiento)
        if v_current > 0 and leak == 0:
            leak = 1
        elif v_current < 0 and leak == 0:
            leak = -1

        # 3. Ecuación diferencial discreta: V(t+1) = V(t) - leak + I_syn
        v_next = v_current - leak + int(i_val)

        # Saturación inferior en el límite de hiperpolarización biológica (-250)
        if v_next < int(self.v_reset):
            v_next = int(self.v_reset)

        # 4. Evaluación de umbral y generación de potencial de acción (Spike)
        if v_next > int(self.v_th):
            self.spike = np.uint8(1)
            self.v_mem = self.v_reset  # Hiperpolarización post-disparo
            self.refr_cnt = self.refrac_ticks
        else:
            self.v_mem = np.int16(v_next)

        return self.v_mem, self.spike, self.refr_cnt


def generate_benchmark_stimulus(n_steps: int = 1000) -> np.ndarray:
    """
    Construye un protocolo de estimulación sintético de 1000 pasos (20 segundos)
    diseñado para ejercitar y validar todas las facetas dinámicas del hardware:
      - 0 - 50 ticks   (0.0 - 1.0 s) : Reposo / Línea base (I = 0)
      - 50 - 250 ticks  (1.0 - 5.0 s) : Excitación tónica constante (I = +68) -> Tren regular
      - 250 - 380 ticks (5.0 - 7.6 s) : Relajación pasiva por fuga (I = 0)
      - 380 - 580 ticks (7.6 - 11.6 s): Alta excitación (I = +95) -> Mayor frecuencia de disparo
      - 580 - 700 ticks (11.6 - 14.0 s): Inhibición activa (I = -65) -> Bloqueo a -250
      - 700 - 880 ticks (14.0 - 17.6 s): Tren de impulsos estocásticos tipo Poisson
      - 880 - 1000 ticks (17.6 - 20.0 s): Retorno final a reposo (I = 0)
    """
    stimulus = np.zeros(n_steps, dtype=np.int16)

    # Fase 1: Excitación regular tónica (+68)
    stimulus[50:250] = np.int16(68)

    # Fase 2: Reposo (0) - Ya inicializado en ceros

    # Fase 3: Excitación fuerte (+95)
    stimulus[380:580] = np.int16(95)

    # Fase 4: Inhibición sostenida (-65)
    stimulus[580:700] = np.int16(-65)

    # Fase 5: Estímulos estocásticos tipo Poisson / Pulsos sinápticos
    np.random.seed(42)  # Reproducibilidad científica
    poisson_pulses = np.random.poisson(lam=0.25, size=180)
    burst_current = np.clip(poisson_pulses * 70, 0, 140).astype(np.int16)
    stimulus[700:880] = burst_current

    # Fase 6: Retorno a reposo
    stimulus[880:1000] = np.int16(0)

    return stimulus


def run_equivalence_simulation(n_steps: int = 1000, 
                               stimulus: np.ndarray = None,
                               dt_ms: float = 20.0) -> dict:
    """
    Ejecuta la emulación completa ciclo a ciclo utilizando arreglos NumPy optimizados.
    """
    if stimulus is None:
        stimulus = generate_benchmark_stimulus(n_steps)
    else:
        n_steps = len(stimulus)

    time_steps = np.arange(n_steps, dtype=np.int32)
    time_ms = time_steps * dt_ms
    time_s = time_ms / 1000.0

    v_mem_arr = np.zeros(n_steps, dtype=np.int16)
    spike_arr = np.zeros(n_steps, dtype=np.uint8)
    refr_arr = np.zeros(n_steps, dtype=np.int16)

    neuron = FixedPointLIFNeuron(v_th=1000, v_reset=-250, refrac_ticks=16)

    for t in range(n_steps):
        v, spk, refr = neuron.step(stimulus[t])
        v_mem_arr[t] = v
        spike_arr[t] = spk
        refr_arr[t] = refr

    return {
        "n_steps": n_steps,
        "dt_ms": dt_ms,
        "time_steps": time_steps,
        "time_ms": time_ms,
        "time_s": time_s,
        "current": stimulus,
        "v_mem": v_mem_arr,
        "spike": spike_arr,
        "refractory": refr_arr,
    }


def save_simulation_csv(data: dict, output_path: str):
    """
    Guarda los 1000 pasos de tiempo en un archivo CSV estructurado para
    correlación directa con la telemetría UART de la FPGA Tang Nano 9K.
    """
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    header = "step,time_ms,time_s,i_syn,v_mem,spike,refractory"
    rows = np.column_stack([
        data["time_steps"],
        np.round(data["time_ms"], 1),
        np.round(data["time_s"], 3),
        data["current"],
        data["v_mem"],
        data["spike"],
        data["refractory"]
    ])
    np.savetxt(output_path, rows, delimiter=",", header=header, comments="", fmt=["%d", "%.1f", "%.3f", "%d", "%d", "%d", "%d"])
    print(f"[INFO] Datos de emulación CSV exportados exitosamente a:\n       -> {os.path.abspath(output_path)}")


def plot_simulation_results(data: dict, output_fig_path: str, show: bool = False):
    """
    Genera una figura científica de 3 subplots estilizada para publicaciones
    y presentaciones de ingeniería de hardware neuromórfico.
    """
    time_s = data["time_s"]
    v_mem = data["v_mem"]
    current = data["current"]
    spikes = data["spike"]
    refr = data["refractory"]

    total_spikes = int(np.sum(spikes))
    mean_rate = total_spikes / (data["n_steps"] * (data["dt_ms"] / 1000.0))

    # Paleta de colores científica moderna (Dark Theme de alto contraste)
    fig, (ax1, ax2, ax3) = plt.subplots(
        3, 1, figsize=(13, 8.5), sharex=True,
        gridspec_kw={"height_ratios": [3.2, 1.3, 1.0]}
    )
    fig.patch.set_facecolor("#0b0e14")

    for ax in (ax1, ax2, ax3):
        ax.set_facecolor("#151922")
        ax.grid(True, linestyle="--", linewidth=0.5, alpha=0.35, color="#7d8590")
        ax.tick_params(colors="#c9d1d9", labelsize=9)
        for spine in ax.spines.values():
            spine.set_color("#30363d")

    # -------------------------------------------------------------------------
    # Panel 1: Potencial de Membrana V(t)
    # -------------------------------------------------------------------------
    ax1.plot(time_s, v_mem, color="#38bdf8", linewidth=1.5, label="Potencial $V(t)$ [16-bit]")
    ax1.axhline(1000, color="#f43f5e", linestyle="--", linewidth=1.4, label="Umbral $V_{TH} = +1000$")
    ax1.axhline(0, color="#94a3b8", linestyle=":", linewidth=1.0, label="Reposo $V_{REST} = 0$")
    ax1.axhline(-250, color="#eab308", linestyle="--", linewidth=1.3, label="Hiperpolarización $V_{RESET} = -250$")

    # Marcar los spikes con marcadores prominentes
    spike_indices = np.where(spikes == 1)[0]
    if len(spike_indices) > 0:
        ax1.scatter(
            time_s[spike_indices], [1000] * len(spike_indices),
            color="#ff0055", s=90, zorder=6, edgecolors="#ffffff", linewidths=1.2,
            label=f"Spikes Disparados (Total: {total_spikes} | Frec. Media: {mean_rate:.1f} Hz)"
        )

    ax1.set_ylabel("Potencial $V_{mem}$ [unidades]", color="#e2e8f0", fontsize=11, fontweight="bold")
    ax1.set_title(
        "Emulación de Equivalencia RTL Ciclo a Ciclo: Neurona LIF en Punto Fijo (50 Hz / 16-bit)",
        color="#f8fafc", fontsize=13, fontweight="bold", pad=12
    )
    ax1.legend(loc="upper right", facecolor="#1e2430", edgecolor="#3b4252", labelcolor="#e2e8f0", fontsize=9)
    ax1.set_ylim(-320, 1150)

    # -------------------------------------------------------------------------
    # Panel 2: Corriente Sináptica I_syn(t)
    # -------------------------------------------------------------------------
    ax2.step(time_s, current, where="post", color="#10b981", linewidth=1.6, label="Corriente Sináptica $I_{syn}(t)$")
    ax2.axhline(0, color="#64748b", linestyle=":", linewidth=0.8)
    ax2.set_ylabel("Corriente $I_{syn}$", color="#e2e8f0", fontsize=10, fontweight="bold")
    ax2.legend(loc="upper right", facecolor="#1e2430", edgecolor="#3b4252", labelcolor="#e2e8f0", fontsize=9)
    ax2.set_ylim(min(-80, np.min(current) - 15), max(110, np.max(current) + 20))

    # -------------------------------------------------------------------------
    # Panel 3: Raster de Disparo y Refractariedad
    # -------------------------------------------------------------------------
    ax3.step(time_s, refr, where="post", color="#c084fc", linewidth=1.4, label="Ticks Refractarios Restantes (16 máx)")
    if len(spike_indices) > 0:
        ax3.vlines(time_s[spike_indices], ymin=0, ymax=16, color="#f43f5e", linewidth=1.5, alpha=0.85, label="Evento de Disparo (Spike)")
    ax3.set_ylabel("Refractario", color="#e2e8f0", fontsize=10, fontweight="bold")
    ax3.set_xlabel("Tiempo Biológico [segundos] (Paso biológico dt = 20 ms / 50 Hz)", color="#e2e8f0", fontsize=11, fontweight="bold")
    ax3.legend(loc="upper right", facecolor="#1e2430", edgecolor="#3b4252", labelcolor="#e2e8f0", fontsize=9)
    ax3.set_ylim(-1, 18)

    plt.tight_layout()

    os.makedirs(os.path.dirname(os.path.abspath(output_fig_path)), exist_ok=True)
    plt.savefig(output_fig_path, dpi=200, facecolor=fig.get_facecolor(), edgecolor="none")
    print(f"[INFO] Gráfica de equivalencia guardada exitosamente en:\n       -> {os.path.abspath(output_fig_path)}")

    if show:
        try:
            plt.show()
        except Exception:
            pass

    plt.close()


def compare_with_telemetry_csv(sim_data: dict, telemetry_path: str):
    """
    Función analítica de Ciencia de Datos: Compara la serie temporal emulada
    con los datos adquiridos por UART (telemetry_listener.py) de la FPGA Tang Nano 9K.
    Calcula el Error Cuadrático Medio (RMSE) y el coeficiente de correlación R.
    """
    if not os.path.exists(telemetry_path):
        print(f"[WARN] No se encontró el archivo de telemetría: {telemetry_path}")
        return

    print("\n" + "=" * 76)
    print("  ANÁLISIS DE CORRELACIÓN: MODELO DE EQUIVALENCIA vs TELEMETRÍA FPGA")
    print("=" * 76)
    try:
        telemetry = np.genfromtxt(telemetry_path, delimiter=",", names=True)
        t_vmem = telemetry["v_mem"]
        t_spikes = telemetry["spike"]

        n_compare = min(len(sim_data["v_mem"]), len(t_vmem))
        sim_v = sim_data["v_mem"][:n_compare]
        real_v = t_vmem[:n_compare]

        rmse = np.sqrt(np.mean((sim_v - real_v) ** 2))
        corr_matrix = np.corrcoef(sim_v, real_v)
        corr_r = corr_matrix[0, 1] if not np.isnan(corr_matrix[0, 1]) else 0.0

        print(f"  Muestras analizadas : {n_compare}")
        print(f"  RMSE de Membrana    : {rmse:.4f} unidades")
        print(f"  Coeficiente Pearson : R = {corr_r:.4f}")
        print(f"  Total Spikes Emulados: {np.sum(sim_data['spike'][:n_compare])}")
        print(f"  Total Spikes FPGA    : {int(np.sum(t_spikes[:n_compare]))}")
        print("=" * 76 + "\n")
    except Exception as e:
        print(f"[ERROR] Error al procesar comparación con telemetría: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Modelo de Equivalencia Hardware LIF en Punto Fijo (16-bit / 50 Hz)"
    )
    parser.add_argument(
        "--steps", type=int, default=1000,
        help="Número de pasos de tiempo a simular (por defecto: 1000 pasos = 20 s)"
    )
    parser.add_argument(
        "--csv", type=str, default="lif_equivalence_data.csv",
        help="Ruta para exportar los datos a CSV (por defecto: lif_equivalence_data.csv)"
    )
    parser.add_argument(
        "--plot", type=str, default="docs/lif_equivalence_plot.png",
        help="Ruta para guardar la gráfica de simulación (por defecto: docs/lif_equivalence_plot.png)"
    )
    parser.add_argument(
        "--compare", type=str, default=None,
        help="Ruta a un archivo CSV de telemetría de la FPGA para análisis de correlación"
    )
    parser.add_argument(
        "--const-i", type=int, default=None,
        help="Inyectar una corriente constante durante los 1000 pasos en lugar del benchmark"
    )
    args = parser.parse_args()

    print("=" * 76)
    print("  INICIANDO EMULACIÓN DE EQUIVALENCIA HARDWARE LIF EN PUNTO FIJO (16-BIT)")
    print(f"  Pasos: {args.steps} | dt: 20.0 ms | Frecuencia: 50.0 Hz | V_TH: 1000 | V_RESET: -250")
    print("=" * 76)

    # Generación o configuración de estímulo
    if args.const_i is not None:
        stimulus = np.full(args.steps, args.const_i, dtype=np.int16)
        print(f"[MODO] Corriente constante seleccionada: I_syn = {args.const_i}")
    else:
        stimulus = generate_benchmark_stimulus(args.steps)
        print("[MODO] Protocolo multifásico de validación neuromórfica activado.")

    # Ejecución de la simulación
    data = run_equivalence_simulation(n_steps=args.steps, stimulus=stimulus, dt_ms=20.0)

    total_spikes = int(np.sum(data["spike"]))
    print(f"\n[RESULTADOS] Simulación de {args.steps} pasos completada.")
    print(f"  - Tiempo biológico total : {data['time_s'][-1]:.2f} segundos")
    print(f"  - Potencial mínimo/máximo: {np.min(data['v_mem'])} / {np.max(data['v_mem'])} unidades")
    print(f"  - Total Spikes emitidos  : {total_spikes} eventos")
    print(f"  - Tasa de disparo media  : {total_spikes / data['time_s'][-1]:.2f} Hz\n")

    # Guardar CSV
    save_simulation_csv(data, args.csv)
    # También asegurar copia en docs para la suite documental
    docs_csv = os.path.join("docs", os.path.basename(args.csv))
    if os.path.abspath(docs_csv) != os.path.abspath(args.csv):
        save_simulation_csv(data, docs_csv)

    # Graficar
    plot_simulation_results(data, args.plot)

    # Comparación opcional
    if args.compare:
        compare_with_telemetry_csv(data, args.compare)

    print("============================================================================")
    print("  >>> EMULACIÓN COMPLETADA EXITOSAMENTE <<<")
    print("============================================================================")


if __name__ == "__main__":
    main()
