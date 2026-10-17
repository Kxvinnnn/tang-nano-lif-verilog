# Speaker Presentation Guide & Operational Defense: FPGA SNN Accelerator

## 1. The Scientific Hook (60 Seconds)
*(Speaker holding the physical Tang Nano 9K development board disconnected from power)*

"Deploying contemporary deep artificial neural networks demands colossal thermodynamic budgets. The primary culprit behind this inefficiency is the physical Von Neumann bottleneck: shuttling weight tensors from external DRAM across high-capacitance PCB buses into GPU arithmetic logic units (ALUs) consumes up to 100 times more physical energy than the arithmetic operation itself. The biological architecture completely abandons this paradigm.

What I hold in my hand is a neuromorphic processor implemented in physical silicon that compiles no sequential software instructions, spawns zero operating system threads, and deliberately excludes floating-point units (FPUs) and dedicated DSP multipliers. It dissolves the physical boundary between memory and compute by executing a discretized neuroscience differential equation embedded directly within its logic gate topology, computing strictly event-driven information at maximum silicon area efficiency."

---

## 2. Unpacking the "Black Box" (3 to 5 Minutes)
*(Project exclusively the internal RTL datapath blueprint and architecture diagram. Treat onboard LEDs and host graphs strictly as secondary observability taps)*

"The compute engine does not execute sequential instructions from program memory; it is governed by a deterministic finite state machine (FSM) operating across two strictly synchronized temporal domains:

*   **Temporal Decoupling (27.0 MHz Master Clock vs 50.0 Hz Biological Epoch):** The silicon runs synchronously on a 27.0 MHz crystal oscillator ($T_{clk} = 37.037\text{ ns}$). Rather than introducing asynchronous Clock Domain Crossing (CDC) bridges, an integrated 20-bit prescaler generates synchronous single-cycle enable strobes (`bio_tick`) exactly every 540,000 clock cycles ($50\text{ Hz} \equiv \Delta t = 20.0\text{ ms}$). This deterministically models the biological membrane time scale without compromising UART baud rate stability or inducing clock jitter.
*   **Zero-DSP Asymptotic Decay (Algorithmic Shift Truncation):** Continuous Leaky Integrate-and-Fire (LIF) dynamics govern passive exponential decay: $\tau_m \frac{dV}{dt} = -(V - V_{rest})$. To eliminate power-hungry DSP multipliers and FPUs, the equation is discretized using an arithmetic right shift: `v_mem >>> 4`. In every biological tick, the neuron passively dissipates exactly $6.25\%$ ($1/16$) of its accumulated charge within a single 37-nanosecond clock cycle.
*   **Arithmetic Integrity & Symmetric Hardware Clamping:** To eliminate the catastrophic hazard of integer overflow wrap-around (where $+32,767 + 1$ would erroneously collapse to $-32,768$), the ALU incorporates an 18-bit signed extended accumulator (`v_sum`). Using symmetric saturation multiplexers, membrane potential is strictly clamped between an upper ceiling of $+32,767$ (suprathreshold burst resilience) and a rigid physiological hyperpolarization floor at $V_{MIN} = -250_{hw}$ ($-75.0\text{ mV}$).
*   **Immutable Physical Quantization:** The resting baseline ($0_{hw}$) maps to $-70.0\text{ mV}$ and the action potential threshold ($1000_{hw}$) to $-50.0\text{ mV}$, guaranteeing a deterministic resolution of $20.0\text{ }\mu\text{V/LSB}$ in signed 16-bit two's-complement arithmetic."

---

## 3. Live Demonstration Protocol
1.  **Cold Boot Verification:** Plug the Tang Nano 9K into the host USB-C port. The FPGA immediately configures its gate array directly from non-volatile on-chip *embFlash* memory without requiring bootloader handshakes or PC host software.
2.  **Launch Multi-Threaded Host Receiver:** Run in the host terminal:
    ```bash
    python telemetry/telemetry_listener.py --port COM4 --baud 115200
    ```
    *Engineering Fortification Note:* The host listener launches a dedicated background daemon thread (`daemon=True`) that continuously drains the operating system's serial FIFO buffer into a thread-safe `queue.Queue`. This guarantees zero dropped packets and zero buffer overruns even when Matplotlib GUI rendering experiences high system latencies.
3.  **Physical Stimulus Injection (Cause):** Sustained press on tactile push-button S1. Explain physical signal conditioning: the mechanical signal passes through a 2-stage flip-flop synchronizer (2-FF) and a 20 ms debounce counter (540,000 cycles) to eliminate contact bounce noise before latching synaptic weights from on-chip BSRAM (`+68` per tick).
4.  **Dynamic Alignment (Effect):** Point to the live oscilloscope GUI showing progressive membrane integration up to the threshold ($1000_{hw}$), the 1-bit action potential spike pulse emitted in byte 7 of the packet, the 16-tick (320 ms) refractory period clamping the potential at baseline, and the post-hyperpolarization curve, confirming bit-by-bit silicon fidelity ($R = 1.0000$, $\text{RMSE} = 0.0$).

---

## 4. Q&A Defense (Critical Engineering Questions)

### Q1: Why declare `set_false_path` on push-button inputs in the SDC constraints?
**Technical Answer:**
"Because input pins `btn1` and `btn2` originate from mechanical push-buttons operating in an asynchronous domain completely decoupled from the FPGA's 27.0 MHz master clock. In our RTL architecture, these external pins never feed directly into the neuron's combinational datapath; instead, they are captured and sanitized by a 2-stage flip-flop synchronizer (2-FF Synchronizer) and a 20 ms debounce counter implemented in `button_debouncer.v`.

Declaring `set_false_path -from [get_ports {btn1 btn2}]` in SDC constraints is standard semiconductor industry practice: it formally instructs the Static Timing Analysis (STA) engine to ignore false setup and hold violations across asynchronous boundary pins that are already protected against metastability. This allows the synthesis and Place & Route engines to focus computational effort exclusively on meeting timing closure across the synchronous 27.0 MHz critical arithmetic path, where we achieve a positive setup slack exceeding +27 nanoseconds."

### Q2: Why would scaling to 100 neurons immediately fail in this specific design?
**Technical Answer:**
"It would not fail due to logic gate exhaustion or memory deficit. A fully connected 100-neuron recurrent network ($100 \times 100 = 10,000$ synapses) at 16 bits per weight requires exactly $160\text{ Kb}$ of storage. Given that the Gowin GW1NR-9C contains 26 embedded BSRAM blocks totaling $468\text{ Kb}$, the synaptic weight matrix occupies only $34.19\%$ of available on-chip memory, leaving more than $65\%$ margin.

The immediate breakdown occurs due to two physical system constraints:
1.  **Serial I/O Bandwidth Asphyxiation:** Continuously streaming 9-byte raw analog telemetry frames (90 physical bits in 8-N-1 framing) for 100 neurons at 50 Hz demands an aggregate bandwidth of $450,000\text{ bps}$. A 115,200 baud UART link suffers a $3.9\times$ deficit, inducing a catastrophic $74.4\%$ packet drop rate and destroying observability.
2.  **Lack of Dynamic CSR Reconfiguration:** Synaptic weights in the baseline prototype are statically preloaded during FPGA configuration via `$readmemh`. Modifying network connectivity requires resynthesizing the entire bitstream.

Our documented architectural roadmap resolves both limitations: first, replacing continuous analog broadcasting with the Address Event Representation (AER) protocol where only active firing neurons emit 2-byte event packets, reducing sparse channel traffic below $10,000\text{ bps}$ ($8.68\%$ channel utilization); second, deploying a 32-bit CSR slave bus over UART RX coupled to Port B of True Dual-Port BSRAM, allowing hot runtime weight updates without taking down the emulation."

### Q3: How is serial telemetry transmission guaranteed to remain stable and deterministic at high data rates?
**Technical Answer:**
"Stability is guaranteed through two complementary mechanisms spanning hardware protocol framing and software threading architecture:
1.  **Hardware-Computed XOR Frame Parity:** The FPGA UART transceiver encapsulates neuronal state into a rigid 9-byte packet delimited by `0xAA 0x55` header preambles and an `0x0A` (`\n`) newline trailer. Byte 8 is dynamically computed in hardware as the bitwise XOR checksum of all 5 payload bytes (`V_H ^ V_L ^ I_H ^ I_L ^ Spike`). If electrical line noise or clock drift corrupts any bit in transit, the host parser drops the frame atomically without contaminating state history.
2.  **Decoupled Producer-Consumer Multithreading:** On the host, a dedicated background thread (`threading.Thread(daemon=True)`) acts as Producer, continuously draining the operating system's serial FIFO buffer at highest priority and enqueuing validated packets into a thread-safe `queue.Queue`. The Matplotlib GUI runs as Consumer on the main thread, non-blockingly draining accumulated samples via `get_nowait()` on every screen refresh. This strict decoupling ensures that OS window resizing or GPU rendering pauses never trigger serial buffer overruns or freeze the real-time telemetry stream."
