# Guion de Demostración en Vivo (Charla / Presentación Miércoles 4:00 PM)
**Duración Total:** 3 - 5 minutos  
**Orador:** Kevin Mejía Cedeño

---

## Minuto 1: Introducción y Motivación Teórica (0:00 - 1:00)
- **Mensaje Clave:** Superar el cuello de botella de von Neumann mediante computación neuromórfica en hardware dedicado.
- **Acción / Diálogo:** 
  - *"Buenas tardes. Hoy presentamos un acelerador de Redes Neuronales Pulsantes (SNN) implementado directamente en silicio sobre la FPGA Tang Nano 9K."*
  - *"A diferencia de las GPUs que consumen cientos de vatios procesando tensores densos, nuestro modelo biológico Leaky Integrate-and-Fire (LIF) procesa eventos discretos ('spikes') consumiendo apenas milivatios, imitando la eficiencia energética del cerebro humano."*

## Minuto 2: Demostración Física en la Tang Nano 9K (1:00 - 2:00)
- **Mensaje Clave:** Interacción tangible con el hardware en el borde (Edge AI).
- **Acción / Diálogo:** 
  - *"Aquí tengo conectada la placa Tang Nano 9K alimentada por USB. Los LEDs en la parte superior muestran en tiempo real el potencial de membrana de nuestra neurona sintética como una barra termométrica."*
  - *(Acción física)*: *"Al presionar el pulsador S1, inyectamos un estímulo sináptico débil almacenado en la memoria BRAM interna de la FPGA. Observen cómo el potencial de membrana asciende gradualmente."*
  - *(Acción física)*: *"Ahora presiono el pulsador S2, que aplica un peso sináptico fuerte. La neurona alcanza el umbral de disparo ($V_{thresh} = 1000$), emite un pulso ('spike') instantáneo y el LED superior parpadea indicando la activación neuronal."*

## Minuto 3: Telemetría en Vivo y Osciloscopio Python (2:00 - 3:30)
- **Mensaje Clave:** Monitoreo y observabilidad síncrona a alta velocidad.
- **Acción / Diálogo:** 
  - *"Toda esta dinámica interna viaja a través de un enlace UART serial a 115,200 baudios directo a nuestro computador."*
  - *(Acción en pantalla)*: *"Ejecutamos nuestro script de telemetría: `python3 src_py/neuromorphic_live_demo.py --port COM3`."*
  - *"En pantalla podemos observar la traza temporal exacta del potencial de membrana $V_{mem}$ decayendo exponencialmente por la fuga pasiva y los momentos exactos de disparo de los picos neuronales."*

## Minuto 4: Conclusiones y Futuros Pasos (3:30 - 4:00)
- **Mensaje Clave:** Escalabilidad y rigor científico rumbo a publicación.
- **Acción / Diálogo:** 
  - *"Hemos validado con éxito el flujo completo: desde el entrenamiento en Python y la cuantización de pesos hexadecimales, pasando por la simulación con Icarus Verilog, hasta la síntesis y ejecución física en la FPGA sin utilizar herramientas propietarias pesadas."*
  - *"El siguiente paso en nuestro semillero es escalar esta arquitectura a una red multicapa con aprendizaje local STDP (Spike-Timing-Dependent Plasticity). Muchas gracias."*
