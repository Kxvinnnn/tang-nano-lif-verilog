`timescale 1ns / 1ps
module bram_synapse_matrix #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 16,
    parameter MEM_SIZE   = 8,
    parameter HEX_FILE   = "data/pesos_sinapticos.hex"
)(
    input  wire                    clk,
    input  wire                    we,
    input  wire [ADDR_WIDTH-1:0]   addr,
    input  wire [DATA_WIDTH-1:0]   din,
    output reg  [DATA_WIDTH-1:0]   dout
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:MEM_SIZE-1];

    initial begin
        $readmemh(HEX_FILE, ram);
    end

    always @(posedge clk) begin
        if (we) ram[addr] <= din;
        dout <= ram[addr];
    end
endmodule
