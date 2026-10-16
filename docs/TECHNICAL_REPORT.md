# Memoria de Investigación: Emulación Neuromórfica Discreta en Silicio

## 1. Introducción y Marco Teórico
El entrenamiento y la inferencia en redes neuronales profundas (ANNs) sufren una penalización energética masiva debido a la transferencia constante de tensores de coma flotante entre la memoria DRAM y las unidades aritmético-lógicas (ALUs). Este diseño implementa una Spiking Neural Network (SNN) fundamentada en el modelo Leaky Integrate-and-Fire (LIF), que procesa información dispersa (*sparse*) dirigida por eventos, unificando memoria y cómputo a nivel de compuerta lógica.

---

## 2. Modelado Matemático e Implementación Computacional
La ecuación diferencial continua de membrana, $\tau \frac{dV}{dt} = -(V - V_{rest}) + R I_{syn}$, se discretizó mediante el método de integración de Euler hacia adelante parametrizado a 50 Hz ($\Delta t = 20.0$ ms). Para garantizar latencia de un ciclo y alta eficiencia de área, se eliminó el estándar de punto flotante IEEE 754 y el uso de bloques DSP.

$$V[k+1] = V[k] - (V[k] \gg 4) + I_{syn}[k]$$

**Mapeo Dimensional y Precisión Int16:**
* **Estado de reposo ($0_{hw}$):** $-70.0\text{ mV}$.
* **Umbral de disparo ($1000_{hw}$):** $-50.0\text{ mV}$. Establece una resolución LSB estricta de $20.0\text{ }\mu\text{V/LSB}$.
* **Periodo refractario:** Bloqueo absoluto de 16 ticks de reloj biológico ($320\text{ ms}$).

**Aritmética de Saturación y Clamping Hardware:**
El riesgo de desbordamiento circular de enteros (*integer overflow wrap-around*, donde $+32,767 + 1$ colapsa a $-32,768$) se mitigó implementando un acumulador intermedio de 18 bits con signo (`v_sum`). La arquitectura fuerza un techo máximo de $+32,767$ para soportar ráfagas supraluminales, y un piso de saturación rígida en $V_{MIN}$ ($-250_{hw} \equiv -75.0\text{ mV}$) para modelar correctamente el límite electrofisiológico de hiperpolarización.

---

## 3. Diseño Experimental y Telemetría
Para medir el estado interno de la matriz neuronal sin inducir latencias parásitas en la ruta crítica computacional (Observer Effect), se diseñó un módulo transceptor síncrono UART operando a 115200 bps. La telemetría extrae tramas verificables por redundancia XOR: `[0xAA, 0x55, Vmem_H, Vmem_L, Isyn_H, Isyn_L, Spike_Flag, Checksum, 0x0A]`. El coeficiente de Pearson $R=1.0000$ entre la captura física del silicio y el simulador Golden en Python valida determinísticamente la implementación.

---

## 4. Cuellos de Botella y Trabajo Futuro (Roadmap AER y Escalabilidad)
La restricción crítica superada en esta fase fue asegurar el *timing* estático integrando el transmisor UART en la ruta de datos sin inducir *logic pruning* o latencias variables. El escalado hacia redes multicapa densas se analiza bajo tres límites físicos estrictos: memoria interna, ancho de banda de comunicación serie y reconfiguración dinámica en caliente.

### 4.1. Análisis Cuantitativo de Capacidad en Memoria (BSRAM)
Para escalar hacia una red de $N = 100$ neuronas totalmente interconectadas:
* Una red totalmente densa requiere una matriz de pesos de $N \times N = 100 \times 100 = 10,000$ sinapsis.
* Con una precisión de 16 bits con signo (`int16`), el volumen de almacenamiento es:
  $$\text{Memoria Requerida} = 10,000 \times 16\text{ bits} = 160,000\text{ bits} = 160\text{ Kb}$$
* La FPGA Gowin GW1NR-9C integra 26 bloques BSRAM de 18 Kb, totalizando $468\text{ Kb}$ de capacidad on-chip.
* La ocupación de memoria resultante es:
  $$\text{Utilización BSRAM} = \frac{160\text{ Kb}}{468\text{ Kb}} \approx 34.19\%$$

Esta holgura del $65.81\%$ en memoria embebida demuestra analíticamente que la capacidad de almacenamiento de pesos **no constituye el cuello de botella** de la plataforma. La limitante física radica en el colapso del enrutamiento espacial punto a punto (*routing switch box congestion*) y en el ancho de banda del canal de telemetría exterior.

### 4.2. Análisis Crítico de Ancho de Banda y Asfixia de I/O (UART Bottleneck y Roadmap AER)
El escalado a 100 nodos enfrenta una barrera matemática estricta impuesta por el canal serie UART tradicional:
* **Sobrecarga de Trama:** En configuración estándar 8-N-1 (1 bit de start + 8 bits de datos + 1 bit de stop), cada byte transmitido requiere 10 bits físicos de canal.
* **Caudal de 1 Nodo:** La trama actual de telemetría consta de 9 bytes (`[0xAA, 0x55, V_H, V_L, I_H, I_L, Spike, XOR_CHK, 0x0A]`), equivalente a $90\text{ bits}$. A una tasa de muestreo biológico de 50 Hz ($\Delta t = 20.0\text{ ms}$):
  $$\text{Tasa de Datos (1 Neurona)} = 90\text{ bits/trama} \times 50\text{ tramas/s} = 4,500\text{ bps}$$
* **Caudal Agregado de 100 Nodos:** Transmitir el estado continuo de membrana de una red de 100 neuronas requeriría:
  $$\text{Demanda de Ancho de Banda} = 100 \times 4,500\text{ bps} = 450,000\text{ bps}$$
* **Colapso del Enlace UART a 115,200 Baudios:**
  $$\text{Déficit de Capacidad} = \frac{450,000\text{ bps}}{115,200\text{ bps}} \approx 3.906 \implies \text{Pérdida de Paquetes} \approx 74.4\%$$
  El canal a 115,200 bps sufriría una asfixia de I/O masiva, perdiendo casi 3 de cada 4 tramas y destruyendo la observabilidad en tiempo real.

* **Solución Arquitectónica (Roadmap AER - Address Event Representation):** En neurociencia computacional, la información útil reside en el instante de disparo (*timing* de spikes) y no en la amplitud continua sub-umbral. Sustituyendo el volcado continuo de $V(t)$ por un protocolo AER donde únicamente los nodos que disparan transmiten su identificador (paquetes de dirección de 2 bytes = 20 bits de canal) ante la ocurrencia de un spike, y considerando una tasa de disparo biológica dispersa (*sparse firing rate* $\le 5\text{ Hz}$ media):
  $$\text{Demanda AER Dispersa} = (100 \times 5\text{ spikes/s}) \times 20\text{ bits/spike} = 10,000\text{ bps}$$
  Esto reduce el consumo del enlace a solo el $8.68\%$ del canal de 115,200 bps, habilitando escalabilidad a cientos de nodos concurrentes.
  Para diagnósticos de laboratorio que requieran osciloscopio analógico completo, se contempla alternativamente elevar la capa física al modo High-Speed del puente integrado (BL702/FT2232) a $1.0\text{ Mbps}$ o $3.0\text{ Mbps}$, o mediante bus SPI de 4 hilos (> 20 MHz).

### 4.3. Reconfiguración Dinámica de Parámetros mediante Bus CSR (Control and Status Registers)
En la implementación actual, la matriz de pesos sinápticos reside en bloques de memoria estática inicializados en tiempo de síntesis mediante directivas `$readmemh` vinculadas al archivo `data/pesos_sinapticos.hex`.

* **Limitación del Silicio Estático:** Cualquier modificación en la conductancia sináptica, topología de interconexión o adaptación plástica exige un ciclo completo de resíntesis, mapeo, ubicación y ruteo (P&R) en Gowin EDA (~30-60 segundos por iteración), imposibilitando la experimentación interactiva o el aprendizaje continuo *on-chip*.
* **Arquitectura de Interfaz CSR:** El roadmap introduce un bus esclavo de Registros de Control y Estado (CSR) acoplado a la línea receptora UART RX o mediante un bus ligero Wishbone/AXI-Lite.
* **Memoria BSRAM de Doble Puerto (True Dual-Port):**
  * **Puerto A (Solo Lectura - Dominio Neuronal):** Direccionado síncronamente por el secuenciador biológico de la neurona a 50 Hz para extraer el peso $I_{syn}[k]$.
  * **Puerto B (Lectura/Escritura - Dominio CSR):** Gobernado por la FSM del bus de comunicaciones, permitiendo escribir nuevos pesos de 16 bits en cualquier posición de memoria en tiempo real durante la emulación activa sin detener el núcleo LIF ni generar pulsos espurios de reloj.
* **Impacto Funcional:** Esta arquitectura desacopla el ciclo de vida del bitstream del ciclo de vida del modelo de aprendizaje, habilitando protocolos de plasticidad dependiente del tiempo de disparo (*Spike-Timing-Dependent Plasticity*, STDP) y validación Hardware-in-the-Loop (HIL) remota desde el host.

---

## 5. Metodología de Validación Energética (Blindaje del Argumento Edge AI)
En arquitecturas neuromórficas Spiking (SNN), las herramientas convencionales de análisis de potencia basadas en software (como Gowin Power Analyzer o estimadores SAIF estáticos) son fundamentalmente incapaces de arrojar métricas de potencia dinámica confiables. Esto se debe a que la actividad de conmutación en una SNN no sigue una distribución gaussiana ni periódica, sino una dinámica estocástica dirigida por eventos escasos (*event-driven sparsity*), donde la disipación energética está estrictamente acoplada a la tasa instantánea de disparo (*firing rate*).

Para obtener mediciones empíricas con rigor de laboratorio, se establece el siguiente protocolo de caracterización física:
1. **Aislamiento de Rieles de Potencia:** Se desvinculan físicamente los dominios de alimentación de la FPGA mediante la apertura de los *solder jumpers* en la PCB de la Tang Nano 9K o la intercepción en serie de la línea VBUS de 5.0 V del conector USB Tipo-C, permitiendo diferenciar el riel de núcleo interno (*Core Logic* $V_{CC} = 1.2\text{ V}$) del riel de periféricos e interfaces (*I/O Banks* $V_{CCO} = 3.3\text{ V}$).
2. **Instrumentación en Derivación (Shunt Current Sensing):** Se inserta una resistencia de sensado no inductiva de precisión ($R_{shunt} = 1.0\text{ }\Omega \pm 0.1\%$) en serie sobre el riel bajo prueba, midiendo la caída de tensión diferencial $\Delta V_{shunt}$ mediante un osciloscopio digital o multímetro de 6½ dígitos de banco (DMM).
3. **Cálculo de Potencia Estática vs Dinámica ($P = V \times I$):**
   * **Potencia en Reposo ($P_{quiescent}$):** Registro de corriente basal $I_{idle}$ (mA) con la neurona en potencial de reposo ($0\text{ Hz}$ de actividad sináptica, $I_{syn} = 0$).
   * **Potencia Dinámica en Ráfaga ($P_{burst}$):** Registro de corriente $I_{active}$ (mA) bajo inyección continua de corriente supraluminal que force un régimen de saturación de disparo ($> 100\text{ Hz}$ de spikes).
   * **Energía Normalizada por Evento:**
     $$E_{spike} = \frac{(I_{active} - I_{idle}) \times V_{CC}}{f_{spike}} \quad [\text{nJ/spike o }\mu\text{W/neurona}]$$

---

## 6. Referencias Bibliográficas
1. Gerstner, W., & Kistler, W. M. (2002). *Spiking Neuron Models: Single Neurons, Populations, Plasticity*. Cambridge University Press. (Fundamentación matemática del modelo LIF).
2. Davies, M., et al. (2018). *Loihi: A Neuromorphic Manycore Processor with On-Chip Learning*. IEEE Micro. (Arquitecturas SNN asíncronas y superación del cuello de botella de Von Neumann).
3. Boahen, K. (2000). *Point-to-point connectivity between neuromorphic chips using address events (AER)*. IEEE Transactions on Circuits and Systems. (Sustento del roadmap para escalabilidad de ruteo).
