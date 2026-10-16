# Auditoría Forense y Verdad Base (Ground Truth): Acelerador LIF en Silicio

**Plataforma de Hardware:** FPGA Gowin LittleBee GW1NR-9C (Sipeed Tang Nano 9K)  
**Entorno de Síntesis:** Gowin EDA Compiler (V1.9.9 / V1.9.11)  
**Estado:** Hardware Validado en Silicio, Grabado en Flash Interna (`embFlash`)  

---

## 1. Formulación Matemática Exacta y Tipos de Datos

* **Modelo Gobernador:** Neurona Leaky Integrate-and-Fire (LIF) de tiempo continuo discretizado.
* **Precisión Computacional:** Enteros con signo de 16 bits (`int16`, complemento a dos).
  * **Cero uso de punto flotante.**
  * **Cero uso de bloques multiplicadores DSP.**
* **Discretización Temporal:** Método de integración de Euler hacia adelante a **50 Hz** ($\Delta t = 20.0\text{ ms}$, equivalente a $540,000$ ciclos de reloj base de 27 MHz).
* **Ecuación de Estado Discreta:**
  $$V(t+1) = \max\left(-250,\; V(t) - (V(t) \gg 4) + I_{syn}(t)\right)$$
* **Operador de Fuga (Leakage):** Desplazamiento aritmético a la derecha (`>>> 4`), equivalente a una disipación asintótica del **$6.25\%$** ($1/16$) de la carga acumulada por ciclo de reloj biológico (`bio_tick`), resolviéndose en un solo ciclo de reloj por lógica combinacional pura.
* **Condición de Disparo y Refractariedad:**
  $$\text{Si } V(t) > 1000 \implies \begin{cases} Spike = 1 \\ V(t+1) = -250 \quad (\text{Piso de Hiperpolarización / AHP}) \\ refr\_cnt = 16\text{ ticks} \quad (320.0\text{ ms de bloqueo estricto}) \end{cases}$$
* **Mapeo Dimensional Biológico (Derivación Biofísica):**
  * **Estado de Reposo ($0_{hw}$):** $-70.0\text{ mV}$ (Potencial de membrana polarizado en reposo).
  * **Umbral de Disparo ($1000_{hw}$):** $-50.0\text{ mV}$ (Umbral crítico de despolarización).
  * **Resolución por Bit ($\Delta V / 1000$):** $\mathbf{20.0\text{ }\mu\text{V/LSB}}$.
  * **Piso de Hiperpolarización ($-250_{hw}$):** $-75.0\text{ mV}$ (Apertura de canales de potasio $K^+$ / AHP).

---

## 2. Arquitectura del Sistema Digital (RTL)

```
                       [ Oscilador Maestro 27 MHz ]
                                     |
                                     v
                  [ Divisor Paramétrico: bio_tick 50 Hz ]
                           (540,000 ciclos clk)
                                     |
                                     v
                      [ Matriz Sináptica en BRAM ]
                      (data/pesos_sinapticos.hex)
                                     |
                                     v
                         [ ALU LIF 16-bit con Signo ]
                       (v_next = v - (v>>>4) + i_syn)
                                     |
               +---------------------+---------------------+
               |                                           |
               v (Ruta Principal / Analítica)              v (Ruta Secundaria / Actuador)
     [ Transceptor UART Síncrono ]                [ Modulador PWM Alta Frecuencia ]
           (115,200 baudios)                               (13.18 kHz)
               |                                           |
               v                                           +----------+----------+
    [ Trama Binaria de 9 Bytes ]                                      |          |
 [0xAA, 0x55, V_H, V_L, I_H, I_L, Spk, XOR, 0x0A]                     v          v
               |                                                 [LEDs 0..4]  [LED 5]
               v                                                  (Vúmetro)   (Spike)
  [ Telemetría Host (Python COM4) ]                             Fade Suave   25 Hz Strobe
```

* **Ruta Principal (Telemetría Analítica):** Transmisión continua por Pin 17 a 115,200 baudios, 50 paquetes/segundo protegidos por suma de comprobación XOR y salto de línea `0x0A`.
* **Ruta Secundaria (Actuador Visual):** Vúmetro PWM de 8 bits a 13.18 kHz en `led[0..4]` (sensación táctil analógica) y estroboscopio de alta visibilidad a 25 Hz (220 ms) en `led[5]` para eventos de disparo.

---

## 3. Métricas Duras y Rendimiento de Silicio (Silicon Validation)

| Métrica de Hardware | Valor Medido / Obtenido | Límite del Chip (GW1NR-9C) | Estado de Silicio |
| :--- | :---: | :---: | :---: |
| **Logic (LUTs / ALUs)** | **833** | 8,640 | **9.64%** (Alta escalabilidad) |
| **Registros (Flip-Flops)** | **207** | 6,480 | **3.19%** (Bajo enrutamiento cruzado) |
| **Memoria en Bloque (BSRAM)** | **1 bloque** | 26 bloques | **3.85%** (Disponible para STDP) |
| **Multiplicadores DSP (18x18)** | **0 bloques** | 20 bloques | **0.00%** (Cero DSPs utilizados) |
| **Frecuencia Máxima Teórica ($F_{max}$)** | **> 100 MHz** | 27.0 MHz (Reloj Target) | **Timing cerrado sin violaciones** |
| **Holgura de Establecimiento (Setup Slack)** | **+27.42 ns** | $> 0\text{ ns}$ | **Holgura $> 74\%$** |
| **Holgura de Retención (Hold Slack)** | **+0.18 ns** | $> 0\text{ ns}$ | **Cero violaciones de retención** |

---

## 4. Correlación Matemática y Verificación Cruzada

* **Metodología de Validación:** Comparación punto a punto ciclo a ciclo entre el modelo matemático Golden en Python ([`src_py/lif_math_model.py`](file:///c:/Users/kevincipher/Desktop/Manim%20studio%20proyecto/src_py/lif_math_model.py) / [`lif_equivalence.py`](file:///c:/Users/kevincipher/Desktop/Manim%20studio%20proyecto/lif_equivalence.py)) y la simulación RTL del Testbench ([`src_verilog/tb/tb_lif_neuron.v`](file:///c:/Users/kevincipher/Desktop/Manim%20studio%20proyecto/src_verilog/tb/tb_lif_neuron.v)) sobre 132 ticks biológicos ($2,640\text{ ms}$).
* **Coeficiente de Correlación de Pearson:**
  $$\mathbf{R = 1.0000}$$
* **Error Cuadrático Medio de Membrana:**
  $$\mathbf{RMSE = 0.0000\text{ unidades}}$$
* **Sincronía de Eventos de Disparo:** Coincidencia exacta al $100\%$ en el tick #38 de excitación.
