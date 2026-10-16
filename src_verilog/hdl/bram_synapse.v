`timescale 1ns / 1ps
// =============================================================================
// bram_synapse.v - Memoria BRAM de Pesos Sinápticos (GW1NR-9C)
// Pragma forzado: (* ram_style = "block" *) para evitar lógica distribuida (LUTs)
// Parametrización estricta de ruta HEX para compatibilidad multiplataforma
// =============================================================================

module bram_synapse #(
    parameter HEX_FILE = "data/pesos_sinapticos.hex"
)(
    input  wire               clk,
    input  wire               we,
    input  wire [2:0]         addr,
    input  wire signed [15:0] din,
    output reg  signed [15:0] dout
);

    // Pragma de síntesis específico para Gowin EDA / Synplify Pro
    (* ram_style = "block" *) reg signed [15:0] ram [0:7];

    initial begin
        $readmemh(HEX_FILE, ram);
    end

    always @(posedge clk) begin
        if (we) begin
            ram[addr] <= din;
        end
        dout <= ram[addr];
    end

endmodule
