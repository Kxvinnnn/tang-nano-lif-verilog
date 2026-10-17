`timescale 1ns / 1ps

module top_snn_system #(
    parameter CLK_FREQ         = 27_000_000,
    parameter DEBOUNCE_TIME_MS = 20
)(
    input  wire        clk, 
    input  wire        rst_n, 
    input  wire        uart_rx, 
    output wire        uart_tx, 
    output wire [5:0]  led
);
    // Debouncer and signal conditioning for active-low external reset
    wire rst_pressed_clean;
    button_debouncer #(
        .CLK_FREQ(CLK_FREQ),
        .DEBOUNCE_TIME_MS(DEBOUNCE_TIME_MS)
    ) u_debouncer_rst (
        .clk(clk),
        .btn_async_in(rst_n),
        .btn_clean_out(rst_pressed_clean)
    );

    // Reset synchronizer for Recovery/Removal timing mitigation (AASD)
    reg [1:0] rst_clean_sync = 2'b00;
    always @(posedge clk or posedge rst_pressed_clean) begin
        if (rst_pressed_clean)
            rst_clean_sync <= 2'b00;
        else
            rst_clean_sync <= {rst_clean_sync[0], 1'b1};
    end
    wire rst_n_clean = rst_clean_sync[1];

    wire signed [15:0] current_stimulus = 16'sh0000;
    wire signed [15:0] v_mem;
    wire spike;
    wire signed [15:0] bram_dout;

    lif_neuron u_lif (
        .clk(clk), 
        .rst_n(rst_n_clean), 
        .bio_tick(1'b1), 
        .current_in(current_stimulus), 
        .spike_out(spike), 
        .v_mem(v_mem)
    );

    bram_synapse u_bram (
        .clk(clk), 
        .we(1'b0), 
        .addr(3'd0), 
        .din(16'sd0), 
        .dout(bram_dout)
    );

    uart_transceiver u_uart (
        .clk(clk), 
        .rst_n(rst_n_clean), 
        .tx_start(1'b0), 
        .tx_byte(8'd0), 
        .tx_busy(), 
        .uart_tx(uart_tx)
    );

    assign led = {5'b00000, spike};
endmodule
