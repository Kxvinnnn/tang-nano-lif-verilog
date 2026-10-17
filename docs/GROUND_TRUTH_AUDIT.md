# Forensic Ground Truth Audit: Neuromorphic LIF Accelerator in Silicon

**Hardware Platform:** Gowin LittleBee GW1NR-9C FPGA (Sipeed Tang Nano 9K)  
**Synthesis Toolchain:** Gowin EDA Compiler (V1.9.9 / V1.9.11)  
**Verification Status:** Silicon Validated, Flashed to Internal Non-Volatile Memory (`embFlash`), 100% CI Green  

---

## 1. Exact Mathematical Formulation & Data Representation

* **Governing Model:** Discretized continuous-time Leaky Integrate-and-Fire (LIF) biological neuron.
* **Computational Precision:** 16-bit signed two's-complement integers (`int16` / `16'sd`).
  * **Zero floating-point arithmetic (Zero FPUs).**
  * **Zero dedicated DSP multiplier blocks (Zero DSPs).**
* **Temporal Discretization:** Forward Euler numerical integration at **50.0 Hz** ($\Delta t = 20.0\text{ ms}$, equivalent to $540,000$ base clock cycles at 27.0 MHz).
* **Discrete State Equation:**
  $$V(t+1) = \max\left(-250,\; V(t) - (V(t) \ggg 4) + I_{syn}(t)\right)$$
* **Leakage Operator (Passive Dissipation):** Arithmetic right shift (`>>> 4`), equivalent to dissipating **$6.25\%$** ($1/16$) of accumulated charge per biological tick (`bio_tick`), resolved in a single 37-ns clock cycle via pure combinational logic.
* **Threshold Firing Condition & Refractoriness:**
  $$\text{If } V(t) > 1000 \implies \begin{cases} Spike = 1 \\ V(t+1) = -250 \quad (\text{Hyperpolarization Floor / AHP}) \\ refr\_cnt = 16\text{ ticks} \quad (320.0\text{ ms absolute lockout}) \end{cases}$$
* **Biophysical Dimensional Mapping:**
  * **Resting Baseline ($0_{hw}$):** $-70.0\text{ mV}$ (Polarized resting membrane potential).
  * **Firing Threshold ($1000_{hw}$):** $-50.0\text{ mV}$ (Critical depolarization threshold).
  * **Bit Quantization Resolution ($\Delta V / 1000$):** $\mathbf{20.0\text{ }\mu\text{V/LSB}}$.
  * **Hyperpolarization Floor ($-250_{hw}$):** $-75.0\text{ mV}$ ($K^+$ channel afterhyperpolarization / AHP).

---

## 2. Digital RTL System Architecture

```text
                       [ 27.0 MHz Master Oscillator ]
                                     |
                                     v
                   [ Parametric Prescaler: bio_tick @ 50 Hz ]
                            (540,000 clock cycles)
                                     |
                                     v
                       [ BSRAM Synaptic Matrix ]
                      (data/synaptic_weights.hex)
                                     |
                                     v
                          [ 16-Bit Signed LIF ALU ]
                        (v_next = v - (v>>>4) + i_syn)
                                     |
                +--------------------+--------------------+
                |                                         |
                v (Primary Analytical Datapath)           v (Secondary Actuator Tap)
      [ Synchronous UART Transceiver ]              [ High-Frequency PWM Modulator ]
            (115,200 baud, 8-N-1)                              (13.18 kHz)
                |                                         |
                v                                         +----------+----------+
      [ 9-Byte Binary Packet ]                                       |          |
  [0xAA, 0x55, V_H, V_L, I_H, I_L, Spk, XOR, 0x0A]                   v          v
                |                                               [LEDs 0..4]  [LED 5]
                v                                                (Voltmeter) (Spike)
     [ Host PC Telemetry (COM4) ]                                Smooth Fade 25Hz Strobe
```

* **Primary Datapath (Analytical Telemetry):** Continuous streaming across Pin 17 at 115,200 baud (50 packets/sec) protected by hardware XOR parity checksum and newline termination `0x0A`.
* **Secondary Datapath (Visual Actuators):** 8-bit PWM voltmeter at 13.18 kHz driving `led[0..4]` for organic analog visualization, and high-visibility 25 Hz stroboscopic burst (220 ms) driving `led[5]` upon action potential spike generation.

---

## 3. Hard Silicon Metrics & Utilization (GW1NR-9C)

| Hardware Resource | Measured Silicon Value | Device Capacity (GW1NR-9C) | Architecture Status |
| :--- | :---: | :---: | :---: |
| **Logic (LUT4 / ALUs)** | **833** | 8,640 | **9.64%** (Massive scalability margin) |
| **Registers (Flip-Flops)** | **207** | 6,480 | **3.19%** (Minimal routing congestion) |
| **Block RAM (BSRAM)** | **1 block** | 26 blocks | **3.85%** (Available for STDP plasticity) |
| **DSP Multipliers (18x18)** | **0 blocks** | 20 blocks | **0.00%** (Zero DSPs utilized) |
| **Max Frequency ($F_{max}$)** | **> 100 MHz** | 27.0 MHz (Target Clock) | **Timing closed cleanly** |
| **Worst Setup Slack** | **+27.42 ns** | $> 0\text{ ns}$ | **Timing margin $> 74\%$** |
| **Worst Hold Slack** | **+0.18 ns** | $> 0\text{ ns}$ | **Zero hold violations** |

---

## 4. Mathematical Correlation & Cross-Validation

* **Validation Methodology:** Point-to-point, cycle-by-cycle comparison between the Python Golden Model ([`src_py/lif_math_model.py`](file:///c:/Users/kevincipher/Desktop/Manim%20studio%20proyecto/src_py/lif_math_model.py) / [`lif_equivalence.py`](file:///c:/Users/kevincipher/Desktop/Manim%20studio%20proyecto/lif_equivalence.py)) and the RTL simulation testbench ([`src_verilog/tb/tb_lif_neuron.v`](file:///c:/Users/kevincipher/Desktop/Manim%20studio%20proyecto/src_verilog/tb/tb_lif_neuron.v)) across 132 biological ticks ($2,640\text{ ms}$).
* **Pearson Correlation Coefficient:**
  $$\mathbf{R = 1.0000}$$
* **Membrane Potential Root Mean Square Error:**
  $$\mathbf{RMSE = 0.0000\text{ units}}$$
* **Spike Event Synchronization:** 100% exact coincidence at excitatory tick #38.
