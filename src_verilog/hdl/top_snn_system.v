`timescale 1ns / 1ps
module top_snn_system (
    input wire clk, 
    input wire rst_n, 
    input wire uart_rx, 
    output wire uart_tx, 
    output wire [5:0] led
);
    wire signed [15:0] current_stimulus = 16'sh0000;
    wire signed [15:0] v_mem;
    wire spike;
    wire [15:0] bram_dout;

    lif_neuron u_lif (
        .clk(clk), 
        .rst_n(rst_n), 
        .tick_enable(1'b1), 
        .current_in(current_stimulus), 
        .spike_out(spike), 
        .v_mem(v_mem)
    );

    bram_synapse u_bram (
        .clk(clk), 
        .we(1'b0), 
        .addr(8'd0), 
        .din(16'd0), 
        .dout(bram_dout)
    );

    uart_transceiver u_uart (
        .clk(clk), 
        .rst_n(rst_n), 
        .rx(uart_rx), 
        .tx(uart_tx), 
        .rx_byte(), 
        .rx_ready(), 
        .tx_byte(8'd0), 
        .tx_start(1'b0), 
        .tx_busy()
    );

    assign led = {5'b00000, spike};
endmodule
