# Engineering Datasheet: Embedded Neuromorphic LIF Accelerator on FPGA

## 1. General Project Information
- **Title:** Embedded Neuromorphic Spiking Neural Network (SNN) Accelerator for Edge AI Inference
- **Core Module:** Leaky Integrate-and-Fire (LIF) Neuron Core with BSRAM Synaptic Matrix, PWM Voltmeter, and Serial Telemetry
- **Author / Investigator:** Kevin Mejía Cedeño
- **Affiliation:** Embedded Systems & Neuromorphic Computing Research Group
- **Advisor / Director:** Daniel Arango Sohm
- **Hardware Status:** Silicon Validated, Permanently Flashed to Non-Volatile Internal Flash (`embFlash`)

---

## 2. Target Hardware Platform
- **Development Board:** Sipeed Tang Nano 9K
- **FPGA Device:** Gowin LittleBee GW1NR-LV9QN88PC6/I5 (GW1NR-9C)
- **Process Technology:** 55 nm Low Power CMOS (Gowin Semiconductor)
- **On-Chip Memory:** 64 Mbit PSRAM embedded inside QFN88 package + Internal Non-Volatile Flash
- **Total Chip Resources:**
  - Logic Cells (4-input LUTs): 8,640
  - Registers / Flip-Flops (FFs): 6,480
  - Block RAM (BSRAM 18K/36K bits): 26 blocks (Total 468 Kb)
  - Hardware Multipliers (DSP 18x18): 20
  - Onboard Oscillator: 27.0 MHz (Pin 52)

---

## 3. RTL Digital System Architecture

```text
                +-------------------------------------------------------+
                |                    Tang Nano 9K                       |
                |                                                       |
  Clock 27MHz ->|-> [Prescaler 540k] ----> bio_tick (50 Hz / 20 ms)    |
                |                                |                      |
  Btn S1 (P3) ->|-> [Dual-FF Sync]               v                      |
  Btn S2 (P4) ->|-> [Dual-FF Sync] ------> [lif_neuron.v]               |
                |        |                   ^       |                  |
                |        v                   |       v                  |
                |   [BSRAM Synapse] ---------+     v_mem, spike         |
                |   (synaptic_weights.hex)           |      |           |
                |                                    v      v           |
                |   [PWM Voltmeter 13.2 kHz] <-------+      |           |
                |        |                                  |           |
                |        v                                  v           |
                |   LEDs [0..4] (Analog Potential)     LED [5] (Spike)  |
                |                                                       |
                |   [UART TX 115200 Baud] <-----------------+           |
                |        | (9-byte frame @ 50 Hz)                       |
                |        v                                              |
                |   Pin 17 (UART TX / COM4 to Host PC)                  |
                +-------------------------------------------------------+
```

### 3.1. Biological Clock Generator (`bio_tick`)
- **Base Frequency:** 27.0 MHz ($T_{clk} \approx 37.037\text{ ns}$).
- **Frequency Divider (Prescaler):** 20-bit synchronous counter modulo 540,000.
- **Biological Step Frequency:** Exactly **50.0 Hz** ($\Delta t = 20.0\text{ ms}$).
- **Behavior:** The membrane potential differential equation (integration and passive leak decay) evaluates strictly on each single-cycle strobe of `bio_tick`, decoupling internal dynamics from external asynchronous events.

### 3.2. Mathematical Formulation & Continuous LIF Neuron Core (`lif_neuron.v`)
- **Continuous Differential Membrane Equation:**
  $$\tau_m \frac{dV}{dt} = -(V - V_{rest}) + R \cdot I_{syn}$$
- **Hardware Discretization (Forward Euler Integration at 50 Hz):**
  $$V[k+1] = V[k] - (V[k] \ggg 4) + I_{syn}[k]$$
- **Passive Leakage (Leak):**
  Arithmetic right shift operation (`>>> 4` in Verilog), equivalent to multiplying by $1/16 = 0.0625$. Resolved in 1 single clock cycle via pure combinational logic, **completely avoiding dedicated DSP multiplier blocks**.
- **Arithmetic Precision:** 16-bit signed fixed-point integer (range: $-32,768$ to $+32,767$).
- **Saturation Arithmetic & Hardware Clamping:**
  To prevent catastrophic failures from integer overflow wrap-around (where $+32,767 + 1$ would collapse to $-32,768$), the ALU synthesizes an intermediate 18-bit signed extended adder (`v_sum`). The output stage implements symmetric saturation multiplexers:
  - **Upper Saturation Ceiling:** If $v_{sum} > +32,767$, the register clamps rigidly to $+32,767$.
  - **Lower Saturation Floor:** If $v_{sum} < V_{MIN} (-250)$, the register clamps to $-250$ (biophysical hyperpolarization / AHP limit).
  This guarantees asymptotic numerical stability across high-frequency bursts of excitatory or inhibitory inputs.
- **Physical Dimensional Mapping (Biophysical Derivation):**
  - **Resting State ($0_{hw}$):** $-70.0\text{ mV}$
  - **Spike Threshold ($1000_{hw}$):** $-50.0\text{ mV}$
  - **Resolution per Bit ($\Delta V / 1000$):** $20.0\text{ }\mu\text{V/LSB}$
  - **Hyperpolarization Floor ($-250_{hw}$):** $-75.0\text{ mV}$
  - **Refractory Period:** 16 biological ticks ($320\text{ ms}$) rigidly clamped at baseline.

### 3.3. Synaptic Matrix in BSRAM (`bram_synapse_matrix.v`)
- Implemented using dedicated embedded BSRAM blocks of the Gowin LittleBee architecture.
- Preloaded via hexadecimal coefficient file (`data/synaptic_weights.hex`).
- Calibrated biological current scales:
  - **Sustained Excitation (Button S1):** $I_{syn} = +68$ (reaches spike threshold in 38 ticks $\approx 0.76\text{ s}$).
  - **Active Inhibition (Button S2):** $I_{syn} = -65$ (hyperpolarizes toward $-250$ in 12 ticks $\approx 0.24\text{ s}$).
  - **Resting State (No Stimulus):** $I_{syn} = 0$ (natural asymptotic leak toward $0$).

### 3.4. Analog Voltmeter with PWM Modulation
- **PWM Modulation Frequency:** $\approx 13.18\text{ kHz}$ ($27\text{ MHz} / 2048$, 8-bit free-running ramp).
- LEDs `led[0..4]` represent 5 quantization intervals of $200\text{ mV}$ each:
  - LEDs below the current voltage level illuminate at 100% duty cycle.
  - The LED corresponding to the active interval modulates its duty cycle proportionally to the fractional remainder, yielding a smooth and organic fade-in/fade-out visual response.

### 3.5. Stroboscopic Spike Action Potential Visualizer
- LED `led[5]` is dedicated exclusively to manifesting action potentials.
- Upon spike generation ($v_{next} \ge V_{TH}$):
  - A **25 Hz stroboscopic burst** activates for **220 ms** (5.5 visible high-energy flash cycles).
  - It is immediately followed by a blackout phase of **100 ms**, completing the **320 ms** biological refractory period.

### 3.6. UART Serial Telemetry Link (Pin 17)
- **Data Path:** 27 MHz Oscillator $\rightarrow$ Clock Prescaler (50 Hz bio_tick) $\rightarrow$ BSRAM Matrix $\rightarrow$ 16-bit LIF ALU $\rightarrow$ UART Serializer (115200 bps, 9-byte frame).
- **Parameters:** 115,200 baud, 8 data bits, no parity, 1 stop bit (8-N-1).
- **Packet Rate:** 50 Hz synchronous with each `bio_tick`.
- **9-Byte Binary Packet Structure:**
  `[0xAA, 0x55, V_MEM_H, V_MEM_L, I_SYN_H, I_SYN_L, SPIKE, CHK, 0x0A]`
  - `0xAA, 0x55`: Dual-byte preamble synchronization delimiters.
  - `V_MEM_H, V_MEM_L`: Instantaneous membrane potential (signed 16-bit integer, Big-Endian).
  - `I_SYN_H, I_SYN_L`: Injected synaptic current (signed 16-bit integer, Big-Endian).
  - `SPIKE`: Spike event flag (`0x01` if action potential fired, `0x00` in baseline/subthreshold).
  - `CHK`: Hardware-computed XOR checksum: `V_MEM_H ^ V_MEM_L ^ I_SYN_H ^ I_SYN_L ^ SPIKE`.
  - `0x0A`: Frame termination byte (newline `\n`).

### 3.7. Physical Pinout Mapping (Tang Nano 9K / GW1NR-9C QFN88)

The pin assignments configured in `constraints/tangnano9k.cst` for the GW1NR-LV9QN88PC6/I5 QFN88 package:

| RTL Port | Physical Pin (QFN88) | I/O Standard | Pull Mode | Architectural Function |
| :--- | :---: | :---: | :---: | :--- |
| `clk` | **Pin 52** | LVCMOS33 | None | 27.0 MHz onboard master crystal clock input. |
| `uart_tx` | **Pin 17** | LVCMOS33 | None | Asynchronous UART serial TX (115200 bps, 8-N-1 to USB bridge). |
| `btn1` | **Pin 3** | LVCMOS33 | `PULL_MODE=UP` | Excitatory tactile current input (Pushbutton S1). |
| `btn2` | **Pin 4** | LVCMOS33 | `PULL_MODE=UP` | Inhibitory tactile current input (Pushbutton S2). |
| `led[0]` | **Pin 10** | LVCMOS33 | `DRIVE=8` | Analog PWM Voltmeter: 0 to 200 mV (Active-Low). |
| `led[1]` | **Pin 11** | LVCMOS33 | `DRIVE=8` | Analog PWM Voltmeter: 200 to 400 mV (Active-Low). |
| `led[2]` | **Pin 13** | LVCMOS33 | `DRIVE=8` | Analog PWM Voltmeter: 400 to 600 mV (Active-Low). |
| `led[3]` | **Pin 14** | LVCMOS33 | `DRIVE=8` | Analog PWM Voltmeter: 600 to 800 mV (Active-Low). |
| `led[4]` | **Pin 15** | LVCMOS33 | `DRIVE=8` | Analog PWM Voltmeter: 800 to 1000 mV (Active-Low). |
| `led[5]` | **Pin 16** | LVCMOS33 | `DRIVE=8` | 25 Hz Stroboscopic Spike Indicator (Active-Low). |

#### Pull-Up Resistors & Active-Low Electrical Logic:
On the Sipeed Tang Nano 9K board, tactile switches S1 and S2 connect the FPGA pin directly to GND when mechanically depressed, floating when released. Internal weak pull-up resistors (`PULL_MODE=UP` in CST) prevent floating high-impedance states.
- **Button Released (Idle):** Pull-up biases trace to VDD ($3.3\text{ V}$), delivering logic `'1'`.
- **Button Pressed (Active):** Switch connects trace to GND ($0.0\text{ V}$), pulling to logic `'0'`.
Consequently, the RTL debouncers synchronize and invert the inputs (`!btn1_clean`, `!btn2_clean`), normalizing internal signals so that `'1'` represents an active synaptic injection.

---

## 4. Silicon Metrics & Synthesis Report (Gowin GW1NR-9C)

| Hardware Resource | Utilized | Available on Chip | Occupancy Ratio |
| :--- | :---: | :---: | :---: |
| **Logic (LUT4 / ALUs)** | **833** | 8,640 | **9.64%** |
| **Registers (Flip-Flops)** | **207** | 6,480 | **3.19%** |
| **BSRAM Blocks (18K/36K)** | **1** | 26 | **3.85%** |
| **I/O Pins (IOBs)** | **10** | 64 | **15.62%** |
| **DSP Multipliers (18x18)** | **0** | 20 | **0.00% (Zero DSPs)** |

### 4.1. Static Timing Analysis (STA)
- **Constraint File:** `constraints/tangnano9k.sdc`
- **Target Constraint Frequency:** 27.0 MHz ($T_{clk} = 37.037\text{ ns}$).
- **Calculated Max Frequency ($F_{max}$):** $> 100\text{ MHz}$ (Operating margin $> 3.7\times$).
- **Timing Violations:** 0 Setup violations, 0 Hold violations (Worst setup slack $> +27\text{ ns}$).

### 4.2. Non-Volatile Flash Persistence
- The synthesized bitstream (`impl/pnr/LIF_Hardware.fs`) is burned permanently into the **Internal Flash** (`embFlash`) of the GW1NR-9C using Gowin Programmer:
  ```bash
  programmer_cli.exe --device GW1NR-9C --run 5 --fsFile impl/pnr/LIF_Hardware.fs
  ```
- **Autonomous Operation:** The accelerator boots instantaneously upon power delivery from any standard USB port or battery pack without requiring host software.

---

## 5. Simulation & Verification Procedures

### 5.1. Unit RTL Verification (`tb_lif_neuron.v`)
The testbench evaluates a 132-biological-tick suite verifying all 5 operational phases of the neuron:
```text
[PHASE 0] Asynchronous reset and initial baseline (v_mem = 0, spike = 0)
[PHASE 1] Continuous excitatory injection (+68) -> Spike at Tick #38 (V_TH = 1000)
[PHASE 2] 16-tick refractory period with potential rigidly clamped at baseline
[PHASE 3] Post-refractory integration resumption
[PHASE 4] Inhibitory injection (-65) -> Strict saturation clamp at V_MIN (-250)
[PHASE 5] Symmetric passive exponential leak toward baseline (v_mem -> 0)
```

#### Run with Icarus Verilog (`iverilog` / `vvp`):
```bash
iverilog -g2012 -s tb_lif_neuron -o build/sim_tb_lif_neuron.vvp src_verilog/hdl/lif_neuron.v src_verilog/tb/tb_lif_neuron.v
vvp build/sim_tb_lif_neuron.vvp
```
*Output:* `TESTBENCH PASSED: ALL FUNCTIONAL TESTS VALIDATED (0 errors)`.

### 5.2. System-Level Integration Verification (`tb_top_system.v`)
Verifies full datapath cohesion and contact bounce noise rejection:
```bash
iverilog -g2012 -s tb_top_system -o build/sim_tb_top_system.vvp \
  src_verilog/hdl/button_debouncer.v \
  src_verilog/hdl/bram_synapse_matrix.v \
  src_verilog/hdl/lif_neuron.v \
  src_verilog/hdl/uart_transceiver.v \
  src_verilog/hdl/top_lif_demo.v \
  src_verilog/tb/tb_top_system.v
vvp build/sim_tb_top_system.vvp
```
*Output:* `TESTBENCH PASSED: Top-Level Integration, Debouncer, BRAM, LIF, and UART validated with 0 errors.`

---

### 5.3. Golden Mathematical Model in Python (`src_py/lif_math_model.py`)
Executes discrete-time equations identical to silicon for point-to-point cross-validation:
```bash
python src_py/lif_math_model.py
```
- Validates 100% bit-exact equivalence between the math model and RTL simulation.
- Generates 3-panel validation plot in `docs/lif_validation_curve.png`.

---

### 5.4. Live Hardware Telemetry (`telemetry/telemetry_listener.py`)
Connect Tang Nano 9K to host PC:
```bash
# Graphical real-time oscilloscope:
python telemetry/telemetry_listener.py --port COM4 --baud 115200 --log-csv telemetry_data/captura_telemetria.csv

# Interactive ASCII console oscilloscope:
python telemetry/telemetry_listener.py --port COM4 --console
```

---

### 5.5. 16-Bit Fixed-Point Equivalence Model (`src_py/lif_equivalence.py`)
Cycle-by-cycle emulation over 1,000 time steps ($20.0\text{ seconds}$ continuous):
```bash
python src_py/lif_equivalence.py --steps 1000 --csv docs/lif_equivalence_data.csv --plot docs/lif_equivalence_plot.png
```
- **Correlation Metrics:** Pearson correlation coefficient $R = 1.0000$ and $\text{RMSE} = 0.0000$ against digital hardware registers.
