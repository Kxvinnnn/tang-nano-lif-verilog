# SNN Tang Nano 9K - Hardware Neuromórfico en Borde

Sistema embebido de **Red Neuronal Pulsante (SNN)** de grado industrial implementado sobre la FPGA **Sipeed Tang Nano 9K (GW1NR-LV9QN88PC6/I5)**.

---

## 1. Diagrama de Bloques de la Arquitectura

```text
[Botones S1/S2] ---> [Sincronizador & Debounce (10ms)] ---> [Direccionamiento BRAM]
                                                                  |
[Reloj 27 MHz]  ---> [Divisor Tick 1kHz (27k ciclos)] ---> [Neurona LIF] <---+
                                                                |
                                        +-----------------------+-----------------------+
                                        |                                               |
                                [Salida LEDs 0..5]                             [Transmisor UART 115200]
                                (Termómetro + Spike)                           (Telemetría en Vivo)
```

---

## 2. Estimación de Recursos (FPGA Gowin GW1NR-9C)

| Recurso Lógico | Utilizado | Total Disponible | Porcentaje |
| :--- | :---: | :---: | :---: |
| **LUTs** | ~240 | 8,640 | 2.7% |
| **Registros (FFs)** | ~185 | 6,480 | 2.8% |
| **Bloques BRAM** | 1 | 26 | 3.8% |
| **Frecuencia Máxima ($F_{max}$)** | >120 MHz | 27 MHz (Reloj Target) | Holgado |

---

## 3. Guía Rápida de Comandos (Makefile)

```bash
# 1. Generar matriz de pesos sinápticos cuantizados
make data

# 2. Ejecutar simulación exhaustiva y generar volcado VCD
make sim

# 3. Sintetizar, rutear y empaquetar el bitstream
make synth-open

# 4. Flasear en la memoria SRAM volátil (pruebas rápidas)
make prog-sram

# 5. Flasear en la Flash permanente (para la demostración)
make prog-flash
```

---

## 4. Telemetría Host (Python)

Para conectar la interfaz de monitoreo en tiempo real con selector de puerto y autodetect:

```bash
python3 src_py/neuromorphic_live_demo.py --port COM3
```

---

## 5. Presentación Autónoma

El paquete incluye la presentación en HTML autónomo lista para doble clic:
`presentacion_final/index.html`
