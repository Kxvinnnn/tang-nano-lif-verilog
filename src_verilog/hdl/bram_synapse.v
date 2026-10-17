`timescale 1ns / 1ps
// =============================================================================
// bram_synapse.v - BRAM Synaptic Weight Memory (Gowin GW1NR-9C)
// Synthesis Pragma: (* ram_style = "block" *) to target embedded BSRAM (not LUTs)
// Parameterized hex file path for multiplatform compatibility
// =============================================================================

module bram_synapse #(
    parameter HEX_FILE = "data/synaptic_weights.hex"
)(
    input  wire               clk,
    input  wire               we,
    input  wire [2:0]         addr,
    input  wire signed [15:0] din,
    output reg  signed [15:0] dout
);

    // Explicit synthesis pragma for Gowin EDA / Synplify Pro
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
