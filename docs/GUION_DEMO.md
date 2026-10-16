# Guion de Demostración en Vivo: Acelerador Neuromórfico en FPGA Tang Nano 9K

**Duración Total Estimada:** 4:00 - 5:00 minutos  
**Presentador:** Kevin Mejía Cedeño  
**Director / Evaluador:** Daniel Arango Sohm  
**Objetivo:** Demostrar la viabilidad de inferencia neuromórfica en silicio, su comportamiento físico biológicamente plausible, telemetría continua en tiempo real y verificación formal bit a bit.

---

## Preparación Previa a la Presentación (Checklist de 1 Minuto)

1. **Conectar la Tang Nano 9K** al puerto USB del computador (identificar que aparezca en el Administrador de Dispositivos como `COM4`).
2. Abrir una terminal en el directorio del proyecto con el entorno virtual activado:
   ```cmd
   cd "C:\Users\kevincipher\Desktop\Manim studio proyecto"
   ```
3. Verificar que la pantalla esté lista para mostrar tanto la placa física como la ventana de telemetría / consola.

---

## Minuto 1: Introducción y Planteamiento del Problema (0:00 - 1:00)

### Mensaje Clave:
Superación del cuello de botella de von Neumann mediante computación neuromórfica en hardware dedicado con consumo de milivatios.

### Diálogo y Guion:
> *"Buenas tardes, profesor Daniel y compañeros. Hoy presento los resultados del diseño, implementación en silicio y validación formal de un **acelerador neuromórfico embebido basado en el modelo biológico Leaky Integrate-and-Fire (LIF)**, ejecutándose de forma completamente autónoma sobre la FPGA Gowin GW1NR-9C de la plataforma Tang Nano 9K."*
>
> *"En los sistemas tradicionales de Inteligencia Artificial basados en GPUs o CPUs, el procesamiento de tensores densos demanda decenas o cientos de vatios debido al constante trasiego de datos entre memoria y procesador. Nuestro diseño neuromórfico opera bajo el paradigma de computación orientada a eventos impulsada por reloj biológico: cuando no hay estímulos, la neurona permanece en reposo con un consumo menor a 15 milivatios, integrando corriente y generando disparos solo cuando es estrictamente necesario."*

---

## Minuto 2: Demostración Física en Silicio y Dinámica Continua (1:00 - 2:15)

### Mensaje Clave:
Operación autónoma no volátil (Flash interna), vúmetro analógico PWM orgánico, fuga exponencial pasiva y potencial de acción bioeléctrico.

### Diálogo y Acciones Físicas:
> *(Mostrar la placa en la mano o frente a la cámara, desconectarla y volverla a conectar)*  
> *"Primero, destaco que este diseño está quemado de forma permanente en la memoria **Flash interna no volátil** del chip. No depende de una conexión a la PC para programarse en cada reinicio; al recibir energía de cualquier puerto USB o batería, el sistema arranca al instante."*
>
> *(Señalar los LEDs apagados)*  
> *"La neurona corre a un paso biológico estricto de **50 Hz (cada 20 milisegundos)** generado por un prescaler a partir del oscilador maestro de 27 MHz."*
>
> *(Presionar y mantener presionado el pulsador S1)*  
> *"Ahora voy a aplicar un estímulo excitatorio continuo manteniendo presionado el botón S1. Los pesos sinápticos provienen de un bloque de memoria **BRAM interna**. Noten la suavidad del ascenso en los primeros 5 LEDs: hemos implementado un **vúmetro analógico con modulación PWM a 13.2 kHz**, de modo que el brillo varía orgánicamente según el residuo fraccional del potencial."*
>
> *(Mantener presionado S1 hasta que dispare a los ~0.8 segundos)*  
> *"Al cruzar el umbral de 1000 unidades arbitrarias, observen el sexto LED: se activa una **ráfaga estroboscópica a 25 Hz durante 220 milisegundos**, simbolizando el potencial de acción bioeléctrico, seguido de un apagón de 100 milisegundos. Esto corresponde exactamente al **periodo refractario biológico de 320 milisegundos**, durante el cual la neurona es inmune a nuevos estímulos."*
>
> *(Subir la barra hasta la mitad con S1 y luego soltarlo)*  
> *"Si interrumpo el estímulo a mitad de camino, pueden apreciar la **fuga pasiva simétrica (leak)**: el potencial decae exponencialmente de vuelta a cero sin atascarse gracias a la aritmética adaptativa con signo."*
>
> *(Presionar S2)*  
> *"Finalmente, el pulsador S2 inyecta corriente inhibitoria negativa, empujando el potencial hacia la **hiperpolarización**, donde nuestro circuito satura de forma segura en -250 para evitar desbordamientos numéricos."*

---

## Minuto 3: Telemetría en Vivo por UART (2:15 - 3:30)

### Mensaje Clave:
Observabilidad y telemetría de grado industrial a 115,200 baudios con visualización interactiva.

### Acción en la Computadora:
Lanzar en la terminal el script de escucha interactiva:
```cmd
.venv\Scripts\python.exe telemetry_listener.py --port COM4
```
*(O en su defecto con la bandera `--console` si se prefiere proyectar en terminal)*:
```cmd
.venv\Scripts\python.exe telemetry_listener.py --port COM4 --console
```

### Diálogo y Demostración en Pantalla:
> *"Para garantizar la observabilidad de las variables de estado internas, la FPGA transmite a través de su pin 17 un enlace serial **UART a 115,200 baudios** con tramas de 9 bytes a 50 Hz protegidas por suma de comprobación XOR."*
>
> *(Interactuar con los botones S1 y S2 mientras la gráfica o la consola se actualiza en vivo)*  
> *"En la pantalla pueden observar la traza continua del potencial de membrana $V_{mem}$, la corriente sináptica $I_{syn}$ y los marcadores exactos donde el hardware emite un spike. La gráfica responde en tiempo real con una latencia imperceptible, demostrando la fidelidad de la dinámica diferencial implementada en Verilog."*

---

## Minuto 4: Verificación Formal y Validación Cruzada (3:30 - 4:30)

### Mensaje Clave:
Rigor de ingeniería: coincidencia 100% bit a bit entre el RTL sintetizado, el Testbench y el modelo matemático en Python.

### Acción en la Computadora:
Mostrar la ejecución del testbench y del modelo matemático:
```cmd
# 1. Ejecutar el modelo matemático golden:
.venv\Scripts\python.exe src_py\lif_math_model.py

# 2. Ejecutar la simulación funcional del Testbench:
call C:\oss-cad-suite\environment.bat
vvp build\sim_tb_lif_neuron.vvp
```

### Diálogo de Conclusión:
> *"Todo este desarrollo fue verificado bajo estándares formales de diseño ASIC/FPGA:*
>
> 1. *Desarrollamos un **banco de pruebas en Verilog (`tb_lif_neuron.v`)** que evalúa 132 ticks biológicos, verificando el reset, la curva de integración, el periodo refractario rígido, la hiperpolarización y la fuga pasiva, arrojando **cero errores** y generando formas de onda VCD para análisis en GTKWave o el Gowin Simulator.*
> 2. *Construimos un **modelo de equivalencia en Python (`lif_equivalence.py` y `lif_math_model.py`)** con aritmética fija de 16 bits idéntica al RTL. Como pueden ver en la tabla de comprobación en pantalla, existe una **coincidencia del 100% bit a bit (R = 1.0000, RMSE = 0.0)** entre la ecuación teórica y los registros en silicio.*
> 3. *En términos de silicio, el diseño utiliza apenas **833 LUTs (9.6%) y 207 flip-flops (3.1%)**, dejando más del 90% de la FPGA disponible para escalar a redes multicapa con plasticidad sináptica dependiente del tiempo de disparo (STDP)."*

---

## Preguntas Frecuentes y Respuestas Rápidas (Q&A de Soporte)

**P1: ¿Por qué eligió 50 Hz para el bio_tick y no una frecuencia de megahertzios?**  
*R:* El reloj base de 27 MHz se utiliza para la síntesis de frecuencia, el PWM de los LEDs (a 13.2 kHz) y la UART (a 115.2 kBaud). Sin embargo, la ecuación diferencial de la neurona se actualiza a 50 Hz porque emula la escala temporal de las neuronas biológicas reales (constantes de tiempo de membrana de decenas de milisegundos) y permite la interactividad humana táctil sin requerir microcontroladores intermediarios.

**P2: ¿Cómo se garantiza que no haya desbordamiento aritmético en la resta de la fuga?**  
*R:* En `lif_neuron.v` se implementó una lógica de saturación inferior en el límite de hiperpolarización ($V_{MIN} = -250$) y una fuga simétrica no lineal que si $v_{mem} > 0$ resta $\max(1, v_{mem} \gg 4)$ y si $v_{mem} < 0$ suma $\max(1, |v_{mem}| \gg 4)$, garantizando convergencia asintótica incondicional hacia 0.

**P3: ¿Qué herramienta se utilizó para programar la Flash interna?**  
*R:* Se utilizó `programmer_cli.exe` de Gowin con el parámetro de ejecución `--run 5` (`embFlash Erase,Program`), grabando directamente el archivo `.fs` en el bloque de memoria no volátil embebido en el chip GW1NR-9C.
