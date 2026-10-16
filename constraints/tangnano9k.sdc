// =============================================================================
// Archivo de Restricciones Temporales (SDC) - Gowin GW1NR-9C (Tang Nano 9K)
// =============================================================================

// 1. Definición del reloj maestro físico (27.0 MHz -> Periodo 37.037 ns, 50% duty cycle)
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// 2. Excepciones de análisis estático (STA) para entradas asíncronas
// Justificación: btn1 y btn2 son acondicionados mediante un sincronizador de doble etapa (2-FF)
// y un filtro de rebote mecánico de 540,000 ciclos, eliminando riesgos de metaestabilidad.
set_false_path -from [get_ports {btn1}]
set_false_path -from [get_ports {btn2}]

// 3. Excepciones de análisis estático (STA) para salidas cuasi-estáticas y periféricas
// Justificación: Los LEDs operan como actuadores esclavos PWM/estroboscópicos a frecuencias
// sub-MHz (< 14 kHz) y la línea UART TX opera desacoplada a 115200 bps.
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports {uart_tx}]
