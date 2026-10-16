`timescale 1ns / 1ps
// =============================================================================
// button_debouncer.v - Acondicionador de Señal Físico Industrial
// Topología: Cadena 2-FF de Sincronización + Filtro Antirrebote Parametrizable
// Cumplimiento: Sin dependencia de bloques 'initial', reset determinista (AASD)
// =============================================================================

module button_debouncer #(
    parameter CLK_FREQ         = 27_000_000,
    parameter DEBOUNCE_TIME_MS = 20
)(
    input  wire clk,
    input  wire rst_n,          // Reset síncrono/asíncrono activo en bajo
    input  wire btn_async_in,
    output reg  btn_clean_out
);
    localparam COUNT_MAX = (CLK_FREQ / 1000) * DEBOUNCE_TIME_MS;
    localparam CNT_WIDTH = (COUNT_MAX > 1) ? $clog2(COUNT_MAX) : 1;
    
    // Etapa 1: Prevención de Metaestabilidad (Cadena Doble Flip-Flop)
    // S1/S2 en Tang Nano poseen resistencias Pull-Up (reposo en 1)
    reg sync_0;
    reg sync_1;

    // Etapa 2: Filtro de Rebote Mecánico con Histéresis Temporal
    reg [CNT_WIDTH-1:0] counter;
    reg                 state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0        <= 1'b1; // Reposo con Pull-Up activo
            sync_1        <= 1'b1;
            counter       <= {CNT_WIDTH{1'b0}};
            state         <= 1'b1;
            btn_clean_out <= 1'b0; // Inactivo en reposo
        end else begin
            // Doble Flip-Flop para mitigar metaestabilidad
            sync_0 <= btn_async_in;
            sync_1 <= sync_0;

            if (sync_1 != state) begin
                if (counter >= COUNT_MAX - 1) begin
                    state         <= sync_1;
                    counter       <= {CNT_WIDTH{1'b0}};
                    btn_clean_out <= ~sync_1; // Activo en alto cuando botón está presionado (0 físico)
                end else begin
                    counter <= counter + 1'b1;
                end
            end else begin
                counter <= {CNT_WIDTH{1'b0}};
            end
        end
    end

endmodule
