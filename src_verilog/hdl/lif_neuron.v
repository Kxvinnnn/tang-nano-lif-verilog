`timescale 1ns / 1ps
module lif_neuron (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick_enable,
    input  wire signed [15:0] current_in,
    output reg                spike_out,
    output reg  signed [15:0] v_mem
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_mem <= 16'd0;
            spike_out <= 1'b0;
        end else if (tick_enable) begin
            v_mem <= v_mem + current_in;
            spike_out <= (v_mem >= 16'sh0800);
        end
    end
endmodule
