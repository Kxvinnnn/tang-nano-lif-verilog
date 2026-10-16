`timescale 1ns / 1ps
// =============================================================================
// button_debouncer.v - Acondicionador de Señal Físico
// Topología: 2-FF Synchronizer (Metaestabilidad) + Counter Debouncer (10-20 ms)
// =============================================================================

module button_debouncer #(
    parameter CLK_FREQ         = 27_000_000,
    parameter DEBOUNCE_TIME_MS = 20
)(
    input  wire clk,
    input  wire btn_async_in,
    output reg  btn_clean_out
);
    localparam COUNT_MAX = (CLK_FREQ / 1000) * DEBOUNCE_TIME_MS;
    
    // Etapa 1: Prevención de Metaestabilidad (2-FF Synchronizer)
    reg sync_0, sync_1;
    always @(posedge clk) begin
        sync_0 <= btn_async_in;
        sync_1 <= sync_0;
    end

    // Etapa 2: Filtro de Rebote Mecánico (Counter)
    reg [$clog2(COUNT_MAX)-1:0] counter;
    reg state;

    initial begin
        counter = 0;
        state = 1'b1; // Asumiendo Pull-Up activo
        btn_clean_out = 1'b0;
    end

    always @(posedge clk) begin
        if (sync_1 != state) begin
            counter <= counter + 1;
            if (counter == COUNT_MAX) begin
                state <= sync_1;
                counter <= 0;
                // Invierte la lógica si usas Pull-Up (activo en bajo)
                btn_clean_out <= ~sync_1; 
            end
        end else begin
            counter <= 0;
        end
    end
endmodule
