`timescale 1ns / 1ps
module top_lif_demo (
    input  wire        clk,          // 27 MHz
    input  wire        btn1,         // S1 (activo en bajo)
    input  wire        btn2,         // S2 (activo en bajo)
    output wire        uart_tx,      // UART TX (Pin 17)
    output wire [5:0]  led           // LEDs 0..5 (activos en bajo)
);
    wire rst_n = 1'b1;

    // Sincronización y Antirrebote para S1 y S2
    wire btn1_clean, btn2_clean;
    debounce_sync u_db1 (.clk(clk), .rst_n(rst_n), .btn_in(btn1), .btn_out(btn1_clean));
    debounce_sync u_db2 (.clk(clk), .rst_n(rst_n), .btn_in(btn2), .btn_out(btn2_clean));

    // Divisor de reloj para tick biológico a ~1 kHz (27000 ciclos de 27 MHz)
    reg [14:0] tick_div;
    reg tick_enable;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_div <= 15'd0;
            tick_enable <= 1'b0;
        end else if (tick_div >= 15'd26999) begin
            tick_div <= 15'd0;
            tick_enable <= 1'b1;
        end else begin
            tick_div <= tick_div + 15'd1;
            tick_enable <= 1'b0;
        end
    end

    // Selección de dirección BRAM según botones limpios
    wire [3:0] bram_addr = (!btn1_clean) ? 4'd0 : (!btn2_clean) ? 4'd1 : 4'd0;
    wire signed [15:0] weight_out;

    bram_synapse_matrix #(
        .ADDR_WIDTH(4),
        .DATA_WIDTH(16),
        .MEM_SIZE(8),
        .HEX_FILE("data/pesos_sinapticos.hex")
    ) u_bram (
        .clk(clk),
        .we(1'b0),
        .addr(bram_addr[3:0]),
        .din(16'd0),
        .dout(weight_out)
    );

    wire signed [15:0] current_input = (!btn1_clean || !btn2_clean) ? weight_out : 16'sd0;
    wire signed [15:0] v_mem;
    wire spike;

    lif_neuron u_lif (
        .clk(clk),
        .rst_n(rst_n),
        .tick_enable(tick_enable),
        .current_in(current_input),
        .spike_out(spike),
        .v_mem(v_mem)
    );

    // Estirador de pulso para LED 5 (spike)
    reg [21:0] led_stretch_cnt;
    reg spike_led_vis;
    always @(posedge clk) begin
        if (spike) begin
            spike_led_vis <= 1'b1;
            led_stretch_cnt <= 22'd2700000; // ~100ms a 27MHz
        end else if (led_stretch_cnt > 0) begin
            led_stretch_cnt <= led_stretch_cnt - 1'b1;
        end else begin
            spike_led_vis <= 1'b0;
        end
    end

    // Barra termométrica para LEDs 0..4 basados en v_mem
    wire [4:0] v_bar = v_mem[11:7];

    // Lógica de LEDs (activos en bajo en Tang Nano 9K)
    assign led[4:0] = ~v_bar;
    assign led[5]   = ~spike_led_vis;

    // FSM UART TX (115200 baudios a 27MHz -> ~234 ciclos por bit)
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;

    uart_transceiver u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .rx(1'b1),
        .tx(uart_tx),
        .rx_byte(),
        .rx_ready(),
        .tx_byte(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

endmodule
