# Guion de Ponencia e Instrucción Operativa: Acelerador SNN en FPGA

## 1. El Gancho Científico (60 Segundos)
*(Speaker sosteniendo la placa física Tang Nano 9K desconectada de su alimentación)*

"El despliegue de la Inteligencia Artificial profunda actual requiere de presupuestos termodinámicos masivos. El responsable directo de esta ineficiencia es el cuello de botella de Von Neumann: transferir un tensor de datos desde la memoria DRAM externa hacia las unidades aritmético-lógicas (ALUs) de una GPU consume hasta 100 veces más energía física que la operación matemática en sí. La alternativa biológica abandona por completo este paradigma. 

Lo que presento aquí es un procesador neuromórfico en silicio que no compila código secuencial, no ejecuta hilos de software y carece deliberadamente de unidades de punto flotante (FPU) o multiplicadores DSP. Disuelve la barrera física entre memoria y cálculo ejecutando una ecuación diferencial discreta de neurociencia embebida directamente en su topología de compuertas lógicas, procesando información dirigida por eventos con máxima eficiencia de área."

---

## 2. Explicación de la "Caja Negra" (3 a 5 Minutos)
*(Proyectar exclusivamente el diagrama de flujo y arquitectura interna RTL. Tratar los LEDs y gráficas como meros actuadores esclavos)*

"El núcleo computacional no opera mediante instrucciones secuenciales de CPU; está gobernado por una máquina de estados determinista gobernada por dos dominios temporales estrictamente sincronizados:

*   **Desacoplamiento Temporal (27 MHz vs 50 Hz):** El silicio corre sobre un oscilador maestro síncrono de 27.0 MHz ($T = 37.037\text{ ns}$). En lugar de conmutar dominios asíncronos (CDC), un prescaler digital genera pulsos de habilitación síncrona `bio_tick` de exactamente 1 ciclo de reloj cada 540,000 ciclos ($50\text{ Hz} \equiv \Delta t = 20.0\text{ ms}$). Esto emula con precisión determinista el paso temporal biológico sin alterar la estabilidad del transceptor UART ni generar *clock jitter*.
*   **Fuga Asintótica sin Bloques DSP (Truncamiento Algorítmico):** La dinámica diferencial del modelo LIF continuo exige decaimiento exponencial $\tau \frac{dV}{dt} = -(V - V_{rest})$. Para evitar el consumo crítico de multiplicadores DSP o FPUs, se discretiza mediante un desplazamiento aritmético a la derecha con signo: `v_mem >>> 4`. En cada tick biológico, la neurona pierde el $6.25\%$ de su carga relativa en un único ciclo de reloj de 37 nanosegundos.
*   **Integridad Aritmética y Clamping Hardware:** Para eliminar el riesgo de desbordamiento circular (*wrap-around*, donde $+32,767 + 1$ colapsaría catastróficamente a $-32,768$), la ALU utiliza un acumulador extendido de 18 bits con signo (`v_sum`). Mediante multiplexores de saturación simétrica, el potencial queda estrictamente acotado entre un techo de $+32,767$ (tolerancia a ráfagas supraluminales) y un piso rígido de hiperpolarización en $V_{MIN} = -250_{hw}$ ($-75.0\text{ mV}$).
*   **Resolución LSB Inmutable:** El estado de reposo ($0_{hw}$) corresponde a $-70.0\text{ mV}$ y el umbral de disparo ($1000_{hw}$) a $-50.0\text{ mV}$, garantizando una cuantización exacta de $20.0\text{ }\mu\text{V/LSB}$ en aritmética de 16 bits con signo."

---

## 3. Protocolo de Demostración en Vivo
1.  **Arranque en Frío:** Conectar la Tang Nano 9K al bus USB del host. La FPGA carga inmediatamente el bitstream desde la memoria *embFlash* no volátil sin secuencias de bootloader de software.
2.  **Lanzamiento del Receptor Multihilo:** Ejecutar en el host:
    ```bash
    python telemetry/telemetry_listener.py --port COM4 --baud 115200
    ```
    *Nota de Blindaje:* El receptor inicializa un hilo dedicado en segundo plano (`daemon=True`) que drena continuamente el buffer FIFO serie del sistema operativo hacia una cola `queue.Queue`. Esto protege la integridad del enlace, garantizando cero pérdida de tramas y cero desbordamientos incluso si la ventana gráfica de Matplotlib experimenta latencias de renderizado.
3.  **Inyección de Estímulo Físico (Causa):** Presionar de forma sostenida el botón excitatorio S1. Explicar el acondicionamiento físico: la señal atraviesa un sincronizador de 2 etapas (2-FF) y un filtro de antirrebote de 20 ms que rechaza el ruido metálico transitorio antes de inyectar los pesos leídos de la memoria BSRAM (`+68` por tick).
4.  **Alineación Dinámica (Efecto):** Señalar en el osciloscopio en vivo la integración progresiva de membrana hasta alcanzar el umbral de disparo ($1000_{hw}$), el pulso de spike emitido en el séptimo byte, el bloqueo por periodo refractario de 16 ticks (320 ms) y la caída en hiperpolarización, demostrando la fidelidad de silicio bit a bit ($R=1.0000$).

---

## 4. Q&A Defense (Preguntas Críticas de Ingeniería)

### P1: ¿Por qué ignorar las rutas en el archivo SDC con `set_false_path`?
**Respuesta Técnica:**
"Porque las líneas de entrada `btn1` y `btn2` provienen de pulsadores mecánicos que operan en un dominio temporal completamente asíncrono e independiente del reloj maestro de 27 MHz de la FPGA. En nuestro diseño RTL, estas señales no entran directamente a la lógica combinacional de la neurona, sino que son capturadas e inmunizadas mediante un sincronizador de doble etapa (2-FF Synchronizer) y un contador antirrebote de 540,000 ciclos (20 ms) implementados en `button_debouncer.v`. 

Declarar `set_false_path -from [get_ports {btn1 btn2}]` en las restricciones SDC es la práctica estándar en la industria de semiconductores: instruye formalmente al motor de Análisis de Temporizado Estático (STA) a no calcular falsas violaciones de *setup* y *hold* en pines asíncronos que ya están desacoplados contra metaestabilidad. Esto permite que los algoritmos de síntesis y Place & Route concentren sus iteraciones exclusivamente en cerrar el temporizado de la ruta crítica síncrona del núcleo aritmético de 27 MHz, donde alcanzamos un margen positivo (*slack*) superior a 27 nanosegundos."

### P2: ¿Por qué fallaría escalar a 100 neuronas hoy mismo en este diseño?
**Respuesta Técnica:**
"No fallaría por falta de memoria ni por capacidad de compuertas lógicas. Una red totalmente densa de 100 neuronas ($100 \times 100 = 10,000$ sinapsis) a 16 bits por peso requiere exactamente $160\text{ Kb}$ de almacenamiento. Dado que la Gowin GW1NR-9C integra 26 bloques BSRAM con $468\text{ Kb}$ totales, la matriz de pesos ocuparía apenas el $34.19\%$ de la memoria embebida, dejando más del $65\%$ de holgura.

El colapso inmediato ocurriría por dos factores físicos concretos:
1.  **Asfixia de Ancho de Banda en el Canal Serial:** Para transmitir la telemetría continua de voltaje analógico de 100 nodos a 50 Hz en tramas de 9 bytes (90 bits físicos en 8-N-1), se demandan $450,000\text{ bps}$. El enlace UART a 115,200 baudios sufre un déficit de $3.9\times$, provocando una pérdida masiva del $74.4\%$ de los paquetes de datos y destruyendo la observabilidad.
2.  **Ausencia de un Bus de Registros CSR:** Los pesos sinápticos actuales están grabados estáticamente en la memoria durante la síntesis mediante `$readmemh`. Modificar la matriz sináptica requeriría resintetizar el bitstream completo para cada prueba.

La solución del roadmap que tenemos definida resuelve ambos problemas: primero, sustituir el volcado continuo por el protocolo AER (Address Event Representation) donde solo se transmiten los spikes de nodos activos, reduciendo el tráfico disperso a menos de $10,000\text{ bps}$ ($8.68\%$ del canal); segundo, implementar un bus de control CSR sobre UART RX acoplado al segundo puerto de una BSRAM True Dual-Port, permitiendo la escritura de pesos en caliente durante la emulación activa."

### P3: ¿Cómo se garantiza la estabilidad y determinismo de la recepción serial a altas tasas?
**Respuesta Técnica:**
"Se garantiza mediante dos mecanismos complementarios a nivel de protocolo y de arquitectura de software:
1.  **Validación de Redundancia XOR en Hardware:** El transceptor UART de la FPGA empaqueta el estado en una trama rígida de 9 bytes delimitada por `0xAA 0x55` en la cabecera y `0x0A` en la cola. El octavo byte es calculado dinámicamente en el hardware como el XOR exclusivo de los 5 bytes de datos útiles (`V_H ^ V_L ^ I_H ^ I_L ^ Spike`). Si ocurre cualquier alteración de bit por ruido de línea o desalineación de reloj, el decodificador descarta la trama de forma atómica sin corromper el histórico de datos.
2.  **Arquitectura Multihilo Productor-Consumidor (Decoupled Threading):** En el host, se implementa un hilo dedicado en segundo plano (`threading.Thread(daemon=True)`) que actúa como Productor. Este hilo lee y drena continuamente el buffer FIFO serie del sistema operativo a máxima prioridad y encola las muestras validadas en una cola thread-safe (`queue.Queue`). El hilo principal de Matplotlib actúa como Consumidor, extrayendo las muestras acumuladas mediante `get_nowait()` en cada refresco de pantalla. Este desacoplamiento asegura que los bloqueos de renderizado de la GPU o pausas en el sistema de ventanas del host nunca provoquen un desbordamiento del buffer serie (*buffer overrun*) ni congelamiento del flujo de telemetría."
