# Ficha Técnica de Ingeniería: Acelerador Neuromórfico Embebido LIF en FPGA

## 1. Información General del Proyecto
- **Título:** Acelerador Neuromórfico Embebido SNN para Inferencia en el Borde (Edge AI)
- **Módulo Principal:** Núcleo de Neurona Leaky Integrate-and-Fire (LIF) con Matriz Sináptica BRAM, Vúmetro PWM y Telemetría Serial
- **Autor / Investigador:** Kevin Mejía Cedeño
- **Afiliación:** Semillero de Sistemas Embebidos y Computación Neuromórfica
- **Director / Tutor:** Daniel Arango Sohm
- **Estado del Hardware:** Validado en Silicio, Almacenado en Memoria Flash No Volátil (Internal Flash)

---

## 2. Plataforma de Hardware Destino
- **Placa de Desarrollo:** Sipeed Tang Nano 9K
- **Dispositivo FPGA:** Gowin LittleBee GW1NR-LV9QN88PC6/I5 (GW1NR-9C)
- **Tecnología de Fabricación:** 55 nm Low Power CMOS (Gowin Semiconductor)
- **Memoria Embebida On-Chip:** 64 Mbit PSRAM integrada en encapsulado QFN88 + Flash Interna
- **Recursos Totales del Chip:**
  - Celdas Lógicas (LUTs de 4 entradas): 8,640
  - Registros / Flip-Flops (FFs): 6,480
  - Bloques de Memoria BSRAM (18K/36K bits): 26 bloques (Total 468 Kb)
  - Multiplicadores de Hardware (DSP 18x18): 20
  - Oscilador / Reloj Onboard: 27.0 MHz (Pin 52)

---

## 3. Arquitectura del Sistema Digital RTL

```
                +-------------------------------------------------------+
                |                    Tang Nano 9K                       |
                |                                                       |
  Clock 27MHz ->|-> [Prescaler 540k] ----> bio_tick (50 Hz / 20 ms)    |
                |                                |                      |
  Btn S1 (P3) ->|-> [Doble-FF Sync]              v                      |
  Btn S2 (P4) ->|-> [Doble-FF Sync] ----> [lif_neuron.v]                |
                |        |                   ^       |                  |
                |        v                   |       v                  |
                |   [BRAM Sináptica] --------+     v_mem, spike         |
                |   (pesos_sinapticos.hex)           |      |           |
                |                                    v      v           |
                |   [Vúmetro PWM 13.2 kHz] <---------+      |           |
                |        |                                  |           |
                |        v                                  v           |
                |   LEDs [0..4] (Carga Analógica)      LED [5] (Spike)  |
                |                                                       |
                |   [UART TX 115200 Baud] <-----------------+           |
                |        | (Trama 9 bytes a 50 Hz)                      |
                |        v                                              |
                |   Pin 17 (TX UART / COM4 hacia PC)                    |
                +-------------------------------------------------------+
```

### 3.1. Generador de Tiempo Biológico (`bio_tick`)
- **Frecuencia Base:** 27.0 MHz ($\approx 37.037\text{ ns}$).
- **Divisor de Frecuencia (Prescaler):** Contador síncrono de 20 bits módulo 540,000.
- **Frecuencia del Paso Biológico:** Exactamente **50.0 Hz** ($\Delta t = 20.0\text{ ms}$).
- **Comportamiento:** La ecuación diferencial de membrana (integración y decaimiento pasivo por fuga) se evalúa estrictamente en cada flanco de `bio_tick`, desacoplándose de los eventos asíncronos externos.

### 3.2. Formulación Matemática y Núcleo Neuronal LIF Continuo (`lif_neuron.v`)
- **Ecuación Diferencial Continua de Membrana:**
  $$\tau \frac{dV}{dt} = -(V - V_{rest}) + R I_{syn}$$
- **Discretización Hardware (Integración Euler hacia adelante a 50 Hz):**
  $$V[k+1] = V[k] - (V[k] \gg 4) + I_{syn}[k]$$
- **Fuga Pasiva (Leak):**
  Operación de desplazamiento aritmético a la derecha (`>>> 4` en Verilog), equivalente a multiplicar por $1/16 = 0.0625$. Resuelta en 1 solo ciclo de reloj mediante lógica combinacional, **evitando el uso de bloques multiplicadores DSP**.
- **Precisión Aritmética:** Punto fijo de 16 bits con signo (rango: $-32,768$ a $+32,767$).
- **Aritmética de Saturación y Clamping Hardware:**
  Para prevenir fallos catastróficos por desbordamiento circular de enteros (*integer overflow wrap-around*, donde $+32,767 + 1$ colapsaría a $-32,768$), la ALU sintetiza un sumador intermedio con bits de guarda extendidos a 18 bits con signo (`v_sum`). La etapa de salida implementa multiplexores de saturación condicional:
  - **Techo de saturación positiva:** Si $v_{sum} > +32,767$, el registro se satura rígidamente en $+32,767$.
  - **Piso de saturación negativa:** Si $v_{sum} < V_{MIN} (-250)$, el registro se satura en $-250$ (límite biofísico de hiperpolarización / AHP).
  Esto garantiza estabilidad asintótica y robustez numérica total ante trenes de impulsos excitatorios o inhibitorios de alta frecuencia.
- **Mapeo Físico (Análisis Dimensional Derivado):**
  - **Estado de reposo ($0_{hw}$):** $-70.0\text{ mV}$
  - **Umbral de disparo ($1000_{hw}$):** $-50.0\text{ mV}$
  - **Resolución por bit ($\Delta V / 1000$):** $20.0\text{ }\mu\text{V/LSB}$
  - **Piso de hiperpolarización ($-250_{hw}$):** $-75.0\text{ mV}$
  - **Periodo refractario:** 16 ticks de `bio_tick` ($320\text{ ms}$) bloqueado rígidamente en reposo/hiperpolarización.

### 3.3. Matriz Sináptica en BRAM (`bram_synapse_matrix.v`)
- Implementada mediante bloques BSRAM dedicados de la arquitectura Gowin LittleBee.
- Precargada mediante archivo de inicialización hexadecimal (`pesos_sinapticos.hex`).
- Corrientes calibradas a escala biológica para interacción táctil:
  - **Excitación sostenida (Botón S1):** $I_{syn} = +68$ (alcanza el umbral en 38 ticks $\approx 0.76\text{ s}$).
  - **Inhibición activa (Botón S2):** $I_{syn} = -65$ (hiperpolariza hacia $-250$ en 12 ticks $\approx 0.24\text{ s}$).
  - **Ausencia de estímulo (Reposo):** $I_{syn} = 0$ (fuga natural asintótica hacia $0$).

### 3.4. Vúmetro Analógico con Modulación PWM
- **Frecuencia de Modulación PWM:** $\approx 13.18\text{ kHz}$ ($27\text{ MHz} / 2048$, rampa libre de 8 bits).
- Los LEDs `led[0..4]` representan 5 niveles de cuantización de $200\text{ mV}$ cada uno:
  - Los LEDs por debajo del nivel se iluminan al 100%.
  - El LED del intervalo actual modula su ciclo de trabajo proporcionalmente al residuo fraccional del potencial, produciendo un efecto de desvanecimiento (*fade-in / fade-out*) completamente fluido y orgánico.

### 3.5. Visualizador Estroboscópico de Disparo (Spike Burst)
- El LED `led[5]` está dedicado exclusivamente a la manifestación del potencial de acción.
- Al producirse el disparo ($v_{next} \ge V_{TH}$):
  - Se activa una ráfaga estroboscópica a **25 Hz** durante **220 ms** (5.5 ciclos visibles de alta energía).
  - Seguidamente, entra en un periodo de oscuridad absoluta de **100 ms**, totalizando los **320 ms** del periodo refractario biológico.

### 3.6. Enlace de Telemetría UART Serial (Pin 17)
- **Canal de Datos:** Oscilador 27 MHz $\rightarrow$ Divisor de frecuencia (50 Hz bio_tick) $\rightarrow$ Memoria BRAM (Matriz de pesos) $\rightarrow$ ALU LIF (16 bits) $\rightarrow$ Shift Register UART (115200 bps, 9 bytes/trama).
- **Parámetros:** 115,200 baudios, 8 bits de datos, sin paridad, 1 bit de parada (8-N-1).
- **Frecuencia de Emisión:** 50 Hz síncrona con cada `bio_tick`.
- **Estructura de la Trama Binaria (9 Bytes):**
  `[0xAA, 0x55, V_MEM_H, V_MEM_L, I_SYN_H, I_SYN_L, SPIKE, CHK, 0x0A]`
  - `0xAA, 0x55`: Delimitadores de sincronía de cabecera.
  - `V_MEM_H, V_MEM_L`: Potencial de membrana actual (entero de 16 bits con signo, Big-Endian).
  - `I_SYN_H, I_SYN_L`: Corriente sináptica inyectada (entero de 16 bits con signo, Big-Endian).
  - `SPIKE`: Bandera de disparo (1 bit: `0x01` si hubo spike, `0x00` en reposo).
  - `CHK`: Suma de comprobación XOR: `V_MEM_H ^ V_MEM_L ^ I_SYN_H ^ I_SYN_L ^ SPIKE`.
  - `0x0A`: Byte de fin de trama (salto de línea `\n`).

### 3.7. Topología Física y Mapa de Ruteo de Pines (Tang Nano 9K / GW1NR-9C QFN88)

El mapeo de restricciones físicas implementado en `constraints/tangnano9k_pins.cst` para el encapsulado QFN88 del chip GW1NR-LV9QN88PC6/I5 se detalla en la siguiente tabla:

| Puerto RTL | Pin Físico (QFN88) | Estándar I/O | Modo de Resistencia | Función Arquitectónica |
| :--- | :---: | :---: | :---: | :--- |
| `clk` | **Pin 52** | LVCMOS33 | Ninguna | Entrada de reloj maestro de 27.0 MHz (cristal onboard). |
| `uart_tx` | **Pin 17** | LVCMOS33 | Ninguna | Salida serial asíncrona UART (115200 bps, 8-N-1 hacia COM4). |
| `btn_s1` | **Pin 3** | LVCMOS33 | `PULL_MODE=UP` | Entrada de corriente excitatoria continua (Pulsador S1). |
| `btn_s2` | **Pin 4** | LVCMOS33 | `PULL_MODE=UP` | Entrada de corriente inhibitoria/AHP continua (Pulsador S2). |
| `led[0]` | **Pin 10** | LVCMOS33 | `DRIVE=8` | Actuador PWM analógico: Nivel 0 a 200 mV (Activo en bajo). |
| `led[1]` | **Pin 11** | LVCMOS33 | `DRIVE=8` | Actuador PWM analógico: Nivel 200 a 400 mV (Activo en bajo). |
| `led[2]` | **Pin 13** | LVCMOS33 | `DRIVE=8` | Actuador PWM analógico: Nivel 400 a 600 mV (Activo en bajo). |
| `led[3]` | **Pin 14** | LVCMOS33 | `DRIVE=8` | Actuador PWM analógico: Nivel 600 a 800 mV (Activo en bajo). |
| `led[4]` | **Pin 15** | LVCMOS33 | `DRIVE=8` | Actuador PWM analógico: Nivel 800 a 1000 mV (Activo en bajo). |
| `led[5]` | **Pin 16** | LVCMOS33 | `DRIVE=8` | Indicador estroboscópico de Spike a 25 Hz (Activo en bajo). |

#### Justificación Técnica de Resistencias Pull-Up y Lógica RTL Negada:
En la placa Sipeed Tang Nano 9K, los pulsadores táctiles S1 y S2 conectan la línea física directamente a GND cuando se encuentran presionados mecánicamente, quedando en circuito abierto (flotantes) al soltarse. Para prevenir estados de alta impedancia indeterminados (flotación) que inducirían conmutaciones espurias por acoplamiento de ruido electromagnético ambiental, se activan las resistencias internas débiles de polarización hacia VDD (`PULL_MODE=UP` en el archivo CST).
Como consecuencia eléctrica de esta configuración:
- **Pulsador en reposo (Suelto):** La resistencia pull-up polariza la línea a VDD ($3.3\text{ V}$), entregando un nivel lógico alto (`1'b1`).
- **Pulsador activo (Presionado):** El interruptor deriva la línea a GND ($0.0\text{ V}$), forzando un nivel lógico bajo (`1'b0`).
Por tanto, el diseño RTL sincroniza la entrada y evalúa la señal negada (`~btn_s1_sync` y `~btn_s2_sync` o `!btn_s1_level`), normalizando la polaridad en el dominio de reloj para que un bit `'1'` interno represente la presencia activa del estímulo sináptico.

---

## 4. Métricas de Silicio y Reporte de Síntesis (Gowin GW1NR-9C)

| Recurso de Hardware | Utilizados | Disponibles en Chip | Porcentaje de Ocupación |
| :--- | :---: | :---: | :---: |
| **Logic (LUTs / ALUs)** | **833** | 8,640 | **9.64%** |
| **Registros (Flip-Flops)** | **207** | 6,480 | **3.19%** |
| **Bloques de Memoria BSRAM** | **1** | 26 | **3.85%** |
| **Pines de E/S (IOBs)** | **10** | 64 | **15.62%** |
| **Multiplicadores DSP (18x18)** | **0** | 20 | **0.00% (Cero DSPs)** |

### 4.1. Análisis de Temporizado Estático (Static Timing Analysis - STA)
- **Archivo de Restricciones:** `constraints/tangnano9k.sdc`
- **Frecuencia de Restricción:** Reloj maestro `clk` a 27.0 MHz ($T_{clk} = 37.037\text{ ns}$).
- **Frecuencia Máxima Teórica Calculada ($F_{max}$):** $> 100\text{ MHz}$ ($> 27\text{ MHz}$).
- **Violaciones de Timing:** 0 violaciones de Setup/Hold (holgura de establecimiento positiva $> 27\text{ ns}$).

### 4.2. Persistencia en Memoria Flash No Volátil
- El bitstream final generado (`LIF_Hardware.fs`) se graba permanentemente en la **Internal Flash** del GW1NR-9C mediante Gowin Programmer CLI:
  ```bash
  programmer_cli.exe --device GW1NR-9C --run 5 --fsFile impl/pnr/LIF_Hardware.fs
  ```
- **Operación autónoma:** El acelerador arranca instantáneamente al ser alimentado por cualquier cable USB o powerbank sin requerir software externo en la PC.

---

## 5. Procedimientos de Simulación y Verificación Formal

### 5.1. Simulación RTL con Testbench (`tb_lif_neuron.v`)
El banco de pruebas ejecuta una suite de verificación de 132 ticks biológicos que valida las 5 fases de operación de la neurona:

```
[FASE 0] Reset asíncrono y reposo inicial (v_mem = 0, spike = 0)
[FASE 1] Inyección excitatoria (+68) continua -> Disparo en Tick #38 (V_TH = 1000)
[FASE 2] Periodo refractario de 16 ticks con potencial rígidamente bloqueado en 0
[FASE 3] Reanudación de integración post-refractario
[FASE 4] Inyección inhibitoria (-65) -> Saturación estricta en V_MIN (-250)
[FASE 5] Fuga exponencial pasiva simétrica hacia reposo (v_mem -> 0)
```

#### Ejecución con Icarus Verilog (`iverilog` / `vvp`):
```cmd
call C:\oss-cad-suite\environment.bat
iverilog -g2012 -s tb_lif_neuron -o build\sim_tb_lif_neuron.vvp src_verilog\hdl\lif_neuron.v src_verilog\tb\tb_lif_neuron.v
vvp build\sim_tb_lif_neuron.vvp
```
*Salida:* `TESTBENCH PASSED: TODAS LAS PRUEBAS FUNCIONALES FUERON VALIDADAS (0 errores)`.  
*Archivo de ondas:* Genera `tb_lif_neuron.vcd` para inspección en GTKWave:
```cmd
gtkwave tb_lif_neuron.vcd
```

#### Ejecución con Gowin Simulator / ModelSim:
1. Abrir Gowin EDA y cargar el proyecto `LIF_Hardware.gprj`.
2. Añadir `src_verilog/tb/tb_lif_neuron.v` al árbol de diseño como archivo de simulación.
3. Ir al menú superior: `Tools` $\rightarrow$ `Gowin Simulator` (o `ModelSim`).
4. Seleccionar el módulo de tope `tb_lif_neuron` y presionar `Run -all`.

### 5.1.2. Simulación de Integración a Nivel de Sistema (`tb_top_system.v`)
Verifica la cohesión estructural de la ruta de datos completa y el rechazo de ruido electromecánico antes de la fabricación del bitstream:
- Inyección de tren de pulsos espurios de alta frecuencia (< 1 ms) para certificar el filtrado del `button_debouncer.v`.
- Conexión BRAM a ALU LIF verificando la lectura de pesos `+68` (excitatorio) y `-65` (inhibitorio).
- Disparo neuronal, temporizador de ráfaga estroboscópica y emisión de la trama serial de 9 bytes a 115200 bps por `uart_tx`.
```cmd
iverilog -g2012 -s tb_top_system -o build\sim_tb_top_system.vvp src_verilog\hdl\button_debouncer.v src_verilog\bram_synapse_matrix.v src_verilog\hdl\lif_neuron.v src_verilog\hdl\uart_transceiver.v src_verilog\top_lif_demo.v src_verilog\tb\tb_top_system.v
vvp build\sim_tb_top_system.vvp
```
*Salida:* `TESTBENCH PASSED: Integracion Top-Level, Antirrebote, BRAM, LIF y UART validados sin errores.`

---

### 5.2. Modelo Matemático Golden en Python (`src_py/lif_math_model.py`)
Implementa las ecuaciones discretas idénticas al silicio y realiza una verificación cruzada punto a punto:
```cmd
.venv\Scripts\python.exe src_py\lif_math_model.py
```
- Valida la coincidencia 100% bit-exacta entre el modelo matemático y la simulación RTL.
- Genera la curva temporal de validación de 3 paneles en `docs/lif_validation_curve.png`.

---

### 5.3. Telemetría en Vivo desde la FPGA (`telemetry_listener.py`)
Con la Tang Nano 9K conectada al puerto COM4:

```cmd
# Modo osciloscopio en consola ASCII interactiva (con guardado opcional de telemetría a CSV):
.venv\Scripts\python.exe telemetry_listener.py --port COM4 --console --log-csv fpga_telemetry.csv

# Modo gráfico dinámico en tiempo real (Matplotlib):
.venv\Scripts\python.exe telemetry_listener.py --port COM4 --log-csv fpga_telemetry.csv
```
Permite observar en tiempo real la subida del potencial al presionar S1, la hiperpolarización al presionar S2, el parpadeo de spikes y la curva asintótica de fuga al soltar los pulsadores.

---

### 5.4. Modelo de Equivalencia Hardware en Punto Fijo 16-bit (`lif_equivalence.py`)
Diseñado para emular ciclo a ciclo el hardware digital en punto fijo de 16 bits (`int16`) a 50 Hz durante 1,000 pasos de tiempo ($20.0\text{ segundos}$ continuos de emulación bioeléctrica):

$$\text{Ecuación: } V(t+1) = V(t) - (V(t) \gg 4) + I_{syn}$$
$$\text{Disparo: Si } V(t) > 1000 \implies \text{Spike} = 1,\; V(t) = -250,\; \text{Refractario} = 16\text{ ticks}$$

```cmd
# 1. Ejecutar emulación completa de 1000 pasos, exportar CSV y generar gráfico:
.venv\Scripts\python.exe lif_equivalence.py --steps 1000 --csv lif_equivalence_data.csv --plot docs/lif_equivalence_plot.png

# 2. Correlación directa y cálculo de error (RMSE y R Pearson) contra telemetría FPGA:
.venv\Scripts\python.exe lif_equivalence.py --compare fpga_telemetry.csv
```
- **Exportación CSV:** Genera `lif_equivalence_data.csv` (`step,time_ms,time_s,i_syn,v_mem,spike,refractory`).
- **Gráfica Científica:** Genera `docs/lif_equivalence_plot.png` con análisis temporal de potencial, corriente sináptica y raster de disparo.
- **Métricas de Equivalencia:** Coeficiente de correlación de Pearson $R = 1.0000$ y $\text{RMSE} = 0.0000$ frente a los registros del hardware digital.
