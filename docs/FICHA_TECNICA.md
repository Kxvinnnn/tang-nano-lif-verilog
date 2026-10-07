# Ficha Técnica: Acelerador Neuromórfico Embebido SNN para Inferencia en el Borde (Edge AI)

## 1. Información General del Proyecto
- **Título:** Acelerador Neuromórfico Embebido SNN para Inferencia en el Borde (Edge AI)
- **Autor / Investigador:** Kevin Mejía Cedeño
- **Afiliación:** Semillero de Sistemas Embebidos y Neuromórfica
- **Director / Tutor:** Daniel Arango Sohm
- **Fecha de Entrega / Demostración:** Miércoles, 4:00 PM

---

## 2. Plataforma de Hardware Destino
- **Placa de Desarrollo:** Sipeed Tang Nano 9K
- **Dispositivo FPGA:** Gowin LittleBee GW1NR-LV9QN88PC6/I5 (GW1NR-9C)
- **Tecnología de Fabricación:** 55nm CMOS (Gowin Semiconductor)
- **Recursos Totales del Chip:**
  - Celdas Lógicas (LUTs): 8,640
  - Registros / Flip-Flops (FFs): 6,480
  - Bloques de Memoria BSRAM (36Kb c/u): 26 (Total 936 Kb)
  - Multiplicadores de Hardware (18x18): 20

---

## 3. Métricas de Silicio y Ocupación Estimada
- **Frecuencia Base de Reloj:** 27.0 MHz (cristal onboard)
- **Frecuencia del Paso Biológico (Tick):** 1.0 kHz (generada mediante divisor de frecuencia de 27,000 ciclos)
- **Ocupación de Recursos (P&R NextPNR / Gowin EDA):**
  - **LUTs Utilizadas:** ~240 / 8,640 (~2.7%)
  - **Flip-Flops Utilizados:** ~185 / 6,480 (~2.8%)
  - **Bloques BSRAM Utilizados:** 1 Bloque (almacenamiento de matriz de pesos sinápticos)
  - **Frecuencia Máxima de Operación ($F_{max}$):** > 120.0 MHz (margen de seguridad superior al 300% respecto a los 27 MHz de diseño).
- **Consumo Energético Estimado:**
  - En reposo (idle): < 15 mW
  - Bajo ráfaga de picos activa: ~35 mW

---

## 4. Subsistema de Telemetría y Comunicaciones
- **Protocolo:** UART Asíncrono (TX Pin 17, RX Pin 18)
- **Configuración:** 115,200 baudios, 8 bits de datos, sin paridad, 1 bit de stop (8-N-1)
- **Formato de Trama (4 bytes por paquete, frecuencia de emisión 500 Hz):**
  - `[0xAA]` - Byte de sincronía y cabecera de trama.
  - `[V_MEM_HIGH]` - Byte alto del potencial de membrana actual ($V_{mem}$).
  - `[V_MEM_LOW]` - Byte bajo del potencial de membrana actual ($V_{mem}$).
  - `[FLAGS]` - Estado de banderas (Bit 0: Spike activo, Bit 1: Estado refractario).
