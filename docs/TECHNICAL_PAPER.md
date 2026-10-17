# Research Paper: Discrete Neuromorphic Emulation in Silicon
## Zero-DSP Fixed-Point Leaky Integrate-and-Fire Accelerator with Synchronous BSRAM Synapses on Gowin GW1NR-9C FPGA

**Author:** Kevin Mejía Cedeño  
**Affiliation:** Embedded Systems & Neuromorphic Computing Research Group  
**Target Platform:** Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5)  
**Artifact Status:** Hardware Validated in Silicon, Non-Volatile embFlash Storage, 100% CI Verified  

---

## Abstract
Modern artificial neural networks (ANNs) suffer from massive thermal and latency bottlenecks imposed by the traditional Von Neumann computer architecture, where memory-to-processor tensor transfers consume up to two orders of magnitude more energy than arithmetic compute. This paper presents a hardware-level, event-driven Spiking Neural Network (SNN) Leaky Integrate-and-Fire (LIF) processing core synthesized into gate-level logic on an FPGA. The continuous biological differential equation of the membrane potential is discretized using Forward Euler integration at 50 Hz ($\Delta t = 20.0$ ms) through signed 16-bit fixed-point saturation arithmetic. By evaluating asymptotic exponential decay via an arithmetic right shift (`v_mem >>> 4`), the architecture operates with zero dedicated DSP multipliers, achieving an exact Pearson correlation ($R = 1.0000$, $\text{RMSE} = 0.0$) against theoretical neuroscience golden models. A deterministic 4-stage Power-On Reset synchronizer, 2-FF metastability debouncers, a 13.18 kHz PWM analog voltmeter, and a continuous 115200 bps UART telemetry bus with hardware XOR parity are integrated into the silicon fabric, utilizing only 9.64% of logic cells (833 LUTs) and meeting static timing constraints at 27.0 MHz with >27 ns of positive slack.

---

## 1. Introduction and Theoretical Framework
Biological brains achieve unmatched energy efficiency ($\sim 20$ W for $10^{11}$ neurons and $10^{15}$ synapses) through event-driven temporal sparsity and co-located memory and compute. Conversely, conventional deep learning workloads deployed on GPUs or Von Neumann processors waste significant energy driving high-capacitance DRAM memory buses to execute matrix-vector multiplications.

Spiking Neural Networks (SNNs) bridge this gap by encoding information into discrete, all-or-none electrical pulses (*action potentials* or *spikes*). The Leaky Integrate-and-Fire (LIF) model balances biological fidelity with hardware implementability:
$$\tau_m \frac{dV(t)}{dt} = -(V(t) - V_{rest}) + R \cdot I_{syn}(t)$$
where $\tau_m = R \cdot C_m$ is the membrane time constant, $V_{rest}$ is the resting baseline, and $I_{syn}(t)$ is the incoming synaptic current. When $V(t)$ crosses a critical threshold $V_{th}$, a spike is generated, the membrane potential is reset, and the neuron enters an absolute refractory lockout period during which it cannot generate further action potentials.

---

## 2. Mathematical Modeling and Silicon Architecture

### 2.1. Forward Euler Discretization at 50 Hz
To eliminate floating-point arithmetic (IEEE 754) and costly hardware multipliers, the continuous LIF differential equation is discretized using Forward Euler integration with a biological step $\Delta t = 20.0$ ms ($f_{bio} = 50.0$ Hz):
$$V[k+1] = V[k] - \frac{\Delta t}{\tau_m} (V[k] - V_{rest}) + \frac{\Delta t}{C_m} I_{syn}[k]$$

Setting $V_{rest} = 0_{hw}$ and selecting $\frac{\Delta t}{\tau_m} = 2^{-4} = \frac{1}{16} = 0.0625$ establishes an effective biological time constant $\tau_m = 16 \cdot 20\text{ ms} = 320\text{ ms}$. This choice allows the asymptotic exponential leak to be computed strictly through an arithmetic right shift:
$$V[k+1] = V[k] - (V[k] \ggg 4) + I_{syn}[k]$$

### 2.2. Dimensional Mapping and Int16 Quantization
The physical biological voltages are mapped into a 16-bit signed integer space (`16'sd`):
* **Resting Potential ($0_{hw}$):** $-70.0\text{ mV}$.
* **Action Potential Threshold ($1000_{hw}$):** $-50.0\text{ mV}$.
* **LSB Quantization Resolution:**
  $$\text{LSB} = \frac{-50.0\text{ mV} - (-70.0\text{ mV})}{1000} = \frac{20.0\text{ mV}}{1000} = 20.0\text{ }\mu\text{V/LSB}$$
* **Absolute Refractory Period:** 16 biological ticks ($16 \times 20\text{ ms} = 320\text{ ms}$) clamped at baseline.

### 2.3. Symmetric Saturation Arithmetic and Hardware Clamping
In conventional 16-bit registers, arithmetic overflow wrap-around represents a catastrophic failure mode: $+32,767 + 1$ wraps around to $-32,768$, converting an intense excitatory stimulus into an unphysical deep hyperpolarization.

To prevent this, the datapath incorporates an 18-bit signed extended accumulator (`v_sum`):
```verilog
v_sum = $signed(v_mem) - $signed(leak) + $signed(current_in);

if (v_sum > 18'sd32767)
    v_next = 16'sd32767;          // Upper ceiling clamp
else if (v_sum < V_MIN)
    v_next = V_MIN;                // Physiological floor clamp (-250 hw = -75.0 mV)
else
    v_next = v_sum[15:0];          // Linear pass-through
```
This guarantees strict mathematical monotonicity across all excitation levels.

---

## 3. Experimental Design, Telemetry, and Cross-Validation

### 3.1. Observer-Effect-Free UART Telemetry Bus
Observing internal membrane states without introducing parasitic delays into the critical computing path is achieved through a dedicated synchronous UART serializer operating at 115200 bps (234 clock cycles per bit at 27 MHz).

At each 50 Hz `bio_tick`, the hardware latches `v_mem`, `i_syn`, and `spike` into snapshot registers, serialization is initiated, and an atomic 9-byte binary packet is transmitted:
$$\text{Packet} = [0\text{xAA},\, 0\text{x55},\, V_{mem\_H},\, V_{mem\_L},\, I_{syn\_H},\, I_{syn\_L},\, \text{Spike},\, \text{Checksum},\, 0\text{x0A}]$$
where $\text{Checksum} = V_{mem\_H} \oplus V_{mem\_L} \oplus I_{syn\_H} \oplus I_{syn\_L} \oplus \text{Spike}$.

### 3.2. Bit-Exact Cross-Validation ($R = 1.0000$)
A Python golden model simulating the exact discrete-time transfer function was executed against both the RTL simulator (Icarus Verilog) and physical UART captures from the FPGA over COM4:
* **Pearson Correlation Coefficient:** $R = 1.0000$
* **Root Mean Square Error:** $\text{RMSE} = 0.0000\text{ units}$
* **Checkpoint Identity:** 100% bit-exact across all 132 evaluation cycles.

---

## 4. Scalability Bottleneck Analysis and Future Roadmap

### 4.1. Embedded Memory (BSRAM) Capacity Analysis
For scaling toward a dense recurrent network of $N = 100$ neurons:
* A fully connected matrix requires $N \times N = 10,000$ synapses.
* At 16 bits per signed weight, total required storage is:
  $$\text{Storage Required} = 10,000 \times 16\text{ bits} = 160\text{ Kb}$$
* The Gowin GW1NR-9C integrates 26 embedded BSRAM blocks of 18 Kb each, providing $468\text{ Kb}$ total capacity on-chip.
* Memory utilization:
  $$\text{BSRAM Utilization} = \frac{160\text{ Kb}}{468\text{ Kb}} = 34.19\%$$

This leaves **65.81% of embedded RAM free**, demonstrating that on-chip synaptic storage is **not** the architectural bottleneck.

### 4.2. Bandwidth Choke and the Address Event Representation (AER) Solution
The true physical limit of the single-neuron telemetry architecture lies in serial I/O bandwidth:
* Standard 8-N-1 framing requires 10 physical bits per byte.
* A single neuron streaming 9 bytes at 50 Hz demands:
  $$\text{Bandwidth (1 Neuron)} = 90\text{ bits/packet} \times 50\text{ packets/s} = 4,500\text{ bps}$$
* Streaming 100 continuous neurons over the serial link would require:
  $$\text{Aggregate Bandwidth} = 100 \times 4,500\text{ bps} = 450,000\text{ bps}$$
* Over a 115,200 baud UART link:
  $$\text{Bandwidth Deficit} = \frac{450,000\text{ bps}}{115,200\text{ bps}} = 3.906 \implies \text{Packet Loss} \approx 74.4\%$$

**Architectural Solution (AER Protocol):** In biological neural systems, information is encoded in spike timing, not continuous sub-threshold analog potentials. By migrating to an Address Event Representation (AER) bus—where only active firing neurons emit 2-byte address packets upon spike occurrence—and assuming a sparse biological firing rate of $\le 5\text{ Hz}$:
$$\text{AER Bandwidth (100 Neurons)} = (100 \times 5\text{ spikes/s}) \times 20\text{ bits/spike} = 10,000\text{ bps}$$
This requires only **8.68%** of the 115,200 bps channel, unlocking scalability to hundreds of concurrent nodes.

### 4.3. Dynamic Synaptic Reprogramming via CSR Bus
In the current implementation, synaptic weights are preloaded during FPGA configuration via `$readmemh` from `data/synaptic_weights.hex`.

The next evolutionary step replaces single-port ROM with True Dual-Port BSRAM:
* **Port A (Read-Only, Neuronal Domain):** Clocked at 50 Hz for synchronous synaptic current retrieval.
* **Port B (Read/Write, Control Domain):** Governed by a UART RX Control and Status Register (CSR) slave FSM, enabling dynamic on-the-fly synaptic weight updates without restarting the accelerator or causing clock glitches.

---

## 5. Physical Energy Characterization Methodology
To measure true dynamic energy dissipation in sparse neuromorphic hardware where switching activity depends strictly on firing frequency, the following laboratory protocol is established:
1. **Power Rail Isolation:** Remove the zero-ohm SMD solder jumpers on the Tang Nano 9K PCB or tap the 5.0 V VBUS rail on the USB-C interface to isolate the internal core logic rail ($V_{CC} = 1.2\text{ V}$) from the I/O bank rail ($V_{CCO} = 3.3\text{ V}$).
2. **Precision Shunt Sensing:** Insert a non-inductive current sensing resistor ($R_{shunt} = 1.0\text{ }\Omega \pm 0.1\%$) in series with the core power rail and measure the differential voltage drop $\Delta V_{shunt}$ using a 6½-digit digital multimeter (DMM) or high-bandwidth oscilloscope.
3. **Static vs. Dynamic Power Computation:**
   * Quiescent Power ($P_{quiescent}$): Record baseline current $I_{idle}$ at 0 Hz synaptic activity ($I_{syn} = 0$).
   * Active Burst Power ($P_{burst}$): Record current $I_{active}$ during continuous suprathreshold stimulation (>100 Hz spike train).
   * Normalized Energy per Action Potential:
     $$E_{spike} = \frac{(I_{active} - I_{idle}) \times V_{CC}}{f_{spike}} \quad [\text{nJ/spike}]$$

---

## 6. References
1. Gerstner, W., & Kistler, W. M. (2002). *Spiking Neuron Models: Single Neurons, Populations, Plasticity*. Cambridge University Press.
2. Davies, M., et al. (2018). *Loihi: A Neuromorphic Manycore Processor with On-Chip Learning*. IEEE Micro, 38(1), 82-99.
3. Boahen, K. (2000). *Point-to-point connectivity between neuromorphic chips using address events (AER)*. IEEE Transactions on Circuits and Systems II, 47(5), 416-434.
4. Indiveri, G., et al. (2011). *Neuromorphic silicon neuron circuits*. Frontiers in Neuroscience, 5, 73.
