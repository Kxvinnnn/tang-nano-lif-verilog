`timescale 1ns / 1ps
module bram_synapse (
    input  wire         clk,
    input  wire         we,
    input  wire [7:0]   addr,
    input  wire [15:0]  din,
    output reg  [15:0]  dout
);
    reg [15:0] ram [0:7];
    initial begin
        ram[0] = 16'h0333;
        ram[1] = 16'h0385;
        ram[2] = 16'h03D7;
        ram[3] = 16'h0428;
        ram[4] = 16'h047A;
        ram[5] = 16'h04CC;
        ram[6] = 16'h051E;
        ram[7] = 16'h0570;
    end
    always @(posedge clk) begin
        if (we) ram[addr] <= din;
        dout <= ram[addr];
    end
endmodule
