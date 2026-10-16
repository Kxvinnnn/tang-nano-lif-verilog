`timescale 1ns / 1ps

module uart_transceiver #(
    parameter CLK_FREQ  = 27000000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        tx,
    output reg  [7:0] rx_byte,
    output reg        rx_ready,
    input  wire [7:0] tx_byte,
    input  wire       tx_start,
    output reg        tx_busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 27,000,000 / 115,200 = 234

    // FSM del Transmisor UART (8-N-1)
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    reg [1:0] tx_state = TX_IDLE;
    reg [8:0] tx_clk_cnt = 9'd0;
    reg [2:0] tx_bit_idx = 3'd0;
    reg [7:0] tx_data_reg = 8'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx          <= 1'b1;
            tx_busy     <= 1'b0;
            tx_state    <= TX_IDLE;
            tx_clk_cnt  <= 9'd0;
            tx_bit_idx  <= 3'd0;
            tx_data_reg <= 8'd0;
            rx_byte     <= 8'd0;
            rx_ready    <= 1'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_busy     <= 1'b1;
                        tx_data_reg <= tx_byte;
                        tx_clk_cnt  <= 9'd0;
                        tx_state    <= TX_START;
                    end
                end

                TX_START: begin
                    tx <= 1'b0; // Start bit
                    if (tx_clk_cnt < CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= tx_clk_cnt + 9'd1;
                    end else begin
                        tx_clk_cnt <= 9'd0;
                        tx_bit_idx <= 3'd0;
                        tx_state   <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    tx <= tx_data_reg[tx_bit_idx];
                    if (tx_clk_cnt < CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= tx_clk_cnt + 9'd1;
                    end else begin
                        tx_clk_cnt <= 9'd0;
                        if (tx_bit_idx < 3'd7) begin
                            tx_bit_idx <= tx_bit_idx + 3'd1;
                        end else begin
                            tx_bit_idx <= 3'd0;
                            tx_state   <= TX_STOP;
                        end
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1; // Stop bit
                    if (tx_clk_cnt < CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= tx_clk_cnt + 9'd1;
                    end else begin
                        tx_clk_cnt <= 9'd0;
                        tx_busy    <= 1'b0;
                        tx_state   <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
