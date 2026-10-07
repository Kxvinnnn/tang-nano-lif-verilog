`timescale 1ns / 1ps
module uart_transceiver (
    input wire clk, 
    input wire rst_n, 
    input wire rx, 
    output reg tx,
    output reg [7:0] rx_byte, 
    output reg rx_ready, 
    input wire [7:0] tx_byte, 
    input wire tx_start, 
    output reg tx_busy
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1'b1;
            rx_ready <= 1'b0;
            tx_busy <= 1'b0;
            rx_byte <= 8'd0;
        end else begin
            tx <= 1'b1;
            rx_ready <= 1'b0;
            tx_busy <= 1'b0;
        end
    end
endmodule
