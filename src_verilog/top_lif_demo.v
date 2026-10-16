`timescale 1ns / 1ps

module top_lif_demo #(
    parameter CLK_FREQ         = 27_000_000,
    parameter DEBOUNCE_TIME_MS = 20,
    parameter HEX_FILE         = "data/pesos_sinapticos.hex"
)(
    input  wire        clk,          // Reloj base 27 MHz (Pin 52)
    input  wire        btn1,         // S1 (Pin 3, activo en bajo)
    input  wire        btn2,         // S2 (Pin 4, activo en bajo)
    output wire        uart_tx,      // UART TX (Pin 17)
    output wire [5:0]  led           // LEDs 0..5 (activos en bajo, Pines 10,11,13,14,15,16)
);

    // =========================================================================
    // 0. RESET DETERMINISTA Y PREVENCIÓN DE RECOVERY / REMOVAL (ASIC Best Practice)
    // =========================================================================
    // Reset Synchronizer (2-FF AASD) que desaserta el reset síncronamente con clk
    // garantizando que los Flip-Flops no sufran violaciones de recuperación/remoción.
    reg [3:0] rst_sync = 4'd0;
    always @(posedge clk) begin
        rst_sync <= {rst_sync[2:0], 1'b1};
    end
    wire rst_n = rst_sync[3];

    // =========================================================================
    // 1. GENERADOR DE RELOJ BIOLÓGICO (Prescaler / bio_tick de 50 Hz = 20 ms)
    // 27,000,000 Hz / 50 Hz = 540,000 ciclos de reloj base
    // =========================================================================
    localparam [19:0] CYCLES_50HZ = 20'd540000;
    reg [19:0] bio_cnt;
    reg        bio_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bio_cnt  <= 20'd0;
            bio_tick <= 1'b0;
        end else if (bio_cnt >= CYCLES_50HZ - 20'd1) begin
            bio_cnt  <= 20'd0;
            bio_tick <= 1'b1;
        end else begin
            bio_cnt  <= bio_cnt + 20'd1;
            bio_tick <= 1'b0;
        end
    end

    // =========================================================================
    // 2. ACONDICIONAMIENTO DE ENTRADA FÍSICA (2-FF Sync + Debouncer 20 ms)
    // S1 y S2 son activos en bajo (0 = presionado, 1 = suelto con Pull-Up)
    // Elimina rebotes mecánicos y metaestabilidad antes de excitar la red.
    // =========================================================================
    wire btn1_clean;
    wire btn2_clean;

    button_debouncer #(
        .CLK_FREQ(CLK_FREQ),
        .DEBOUNCE_TIME_MS(DEBOUNCE_TIME_MS)
    ) u_debouncer_s1 (
        .clk(clk),
        .btn_async_in(btn1),
        .btn_clean_out(btn1_clean)
    );

    button_debouncer #(
        .CLK_FREQ(CLK_FREQ),
        .DEBOUNCE_TIME_MS(DEBOUNCE_TIME_MS)
    ) u_debouncer_s2 (
        .clk(clk),
        .btn_async_in(btn2),
        .btn_clean_out(btn2_clean)
    );

    // Mapeo hacia la lógica de niveles: btn1_clean es 1 cuando S1 está presionado
    wire btn_s1_level = ~btn1_clean;
    wire btn_s2_level = ~btn2_clean;

    // =========================================================================
    // 3. INTEGRACIÓN REAL DE LA MATRIZ SINÁPTICA BRAM
    // Modula dinámicamente el direccionamiento según el estímulo y la ráfaga
    // =========================================================================
    reg [1:0] syn_pattern_idx = 2'd0;
    wire spike;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            syn_pattern_idx <= 2'd0;
        end else if (spike) begin
            syn_pattern_idx <= syn_pattern_idx + 2'd1; // Avanza patrón en cada spike
        end
    end

    // Mapeo de direcciones en BRAM (8 posiciones de 16 bits):
    // - Direcciones pares (0, 2, 4, 6): Pesos excitatorios (+68, +68, +70, +68)
    // - Direcciones impares (1, 3, 5, 7): Pesos inhibitorios (-65, -65, -66, -65)
    wire [3:0] bram_addr = (!btn_s2_level) ? {1'b0, syn_pattern_idx, 1'b1} : 
                           (!btn_s1_level) ? {1'b0, syn_pattern_idx, 1'b0} : 
                           4'd0;

    wire signed [15:0] weight_dout;

    bram_synapse_matrix #(
        .ADDR_WIDTH(4),
        .DATA_WIDTH(16),
        .MEM_SIZE(8),
        .HEX_FILE(HEX_FILE)
    ) u_bram (
        .clk(clk),
        .we(1'b0),
        .addr(bram_addr),
        .din(16'd0),
        .dout(weight_dout)
    );

    // Corriente sináptica final alimentada desde BRAM
    wire signed [15:0] i_syn = (!btn_s2_level || !btn_s1_level) ? weight_dout : 16'sd0;

    // =========================================================================
    // 4. NEURONA LIF (Con Hiperpolarización hasta -250 y Refractario de 320 ms)
    // =========================================================================
    wire signed [15:0] v_mem;

    lif_neuron #(
        .V_TH(16'sd1000),
        .V_MIN(-16'sd250),
        .REFRAC_TICKS(5'd16) // 16 ticks * 20 ms = 320 ms
    ) u_lif (
        .clk(clk),
        .rst_n(rst_n),
        .bio_tick(bio_tick),
        .current_in(i_syn),
        .spike_out(spike),
        .v_mem(v_mem)
    );

    // =========================================================================
    // 5. EFECTO VISUAL DE SPIKE: RÁFAGA ESTROBOSCÓPICA (220 ms) + OSCURIDAD (100 ms)
    // Temporizador: 220 ms (5,940,000 ciclos a 27 MHz)
    // Ráfaga estroboscópica en led[5]: alternando cada 20 ms (~25 Hz)
    // =========================================================================
    localparam [22:0] SPIKE_TIMER_CYCLES = 23'd5940000; // 220 ms a 27 MHz
    localparam [19:0] STROBE_HALF_PERIOD = 20'd540000;  // 20 ms a 27 MHz (~25 Hz)

    reg [22:0] spike_timer;
    reg [19:0] strobe_cnt;
    reg        strobe_blink;

    wire spike_active = (spike_timer > 23'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spike_timer  <= 23'd0;
            strobe_cnt   <= 20'd0;
            strobe_blink <= 1'b0;
        end else if (spike) begin
            spike_timer  <= SPIKE_TIMER_CYCLES;
            strobe_cnt   <= STROBE_HALF_PERIOD;
            strobe_blink <= 1'b1;
        end else if (spike_timer > 23'd0) begin
            spike_timer <= spike_timer - 23'd1;
            if (strobe_cnt > 20'd1) begin
                strobe_cnt <= strobe_cnt - 20'd1;
            end else begin
                strobe_cnt   <= STROBE_HALF_PERIOD;
                strobe_blink <= ~strobe_blink; // Alterna a 25 Hz
            end
        end else begin
            strobe_cnt   <= 20'd0;
            strobe_blink <= 1'b0;
        end
    end

    // =========================================================================
    // 6. VÚMETRO ANALÓGICO CON PWM (~13.18 kHz)
    // Proporciona fade-in / fade-out suave entre niveles sin saltos discretos
    // =========================================================================
    reg [10:0] pwm_clk_div;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pwm_clk_div <= 11'd0;
        else
            pwm_clk_div <= pwm_clk_div + 11'd1;
    end
    wire [7:0] pwm_cnt = pwm_clk_div[10:3]; // Contador de 8 bits a 13.18 kHz

    reg [7:0] duty_0, duty_1, duty_2, duty_3, duty_4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            duty_0 <= 8'd0;
            duty_1 <= 8'd0;
            duty_2 <= 8'd0;
            duty_3 <= 8'd0;
            duty_4 <= 8'd0;
        end else if (bio_tick) begin
            // LED 0: 0 a 220
            if (v_mem <= 16'sd0) begin
                duty_0 <= 8'd0;
            end else if (v_mem >= 16'sd220) begin
                duty_0 <= 8'd255;
            end else begin
                duty_0 <= (v_mem * 16'd255) / 16'd220;
            end

            // LED 1: 220 a 440
            if (v_mem <= 16'sd220) begin
                duty_1 <= 8'd0;
            end else if (v_mem >= 16'sd440) begin
                duty_1 <= 8'd255;
            end else begin
                duty_1 <= ((v_mem - 16'sd220) * 16'd255) / 16'd220;
            end

            // LED 2: 440 a 640
            if (v_mem <= 16'sd440) begin
                duty_2 <= 8'd0;
            end else if (v_mem >= 16'sd640) begin
                duty_2 <= 8'd255;
            end else begin
                duty_2 <= ((v_mem - 16'sd440) * 16'd255) / 16'd200;
            end

            // LED 3: 640 a 800
            if (v_mem <= 16'sd640) begin
                duty_3 <= 8'd0;
            end else if (v_mem >= 16'sd800) begin
                duty_3 <= 8'd255;
            end else begin
                duty_3 <= ((v_mem - 16'sd640) * 16'd255) / 16'd160;
            end

            // LED 4: 800 a 920
            if (v_mem <= 16'sd800) begin
                duty_4 <= 8'd0;
            end else if (v_mem >= 16'sd920) begin
                duty_4 <= 8'd255;
            end else begin
                duty_4 <= ((v_mem - 16'sd800) * 16'd255) / 16'd120;
            end
        end
    end

    wire pwm_out_0 = (pwm_cnt < duty_0);
    wire pwm_out_1 = (pwm_cnt < duty_1);
    wire pwm_out_2 = (pwm_cnt < duty_2);
    wire pwm_out_3 = (pwm_cnt < duty_3);
    wire pwm_out_4 = (pwm_cnt < duty_4);

    wire led_bar_en = !spike_active;

    // LEDs son activos en bajo (0 = Encendido, 1 = Apagado)
    assign led[0] = ~(led_bar_en && pwm_out_0);
    assign led[1] = ~(led_bar_en && pwm_out_1);
    assign led[2] = ~(led_bar_en && pwm_out_2);
    assign led[3] = ~(led_bar_en && pwm_out_3);
    assign led[4] = ~(led_bar_en && pwm_out_4);
    assign led[5] = ~(spike_active && strobe_blink);

    // =========================================================================
    // 7. TELEMETRÍA UART EN VIVO A 115200 BAUDIOS (Pin 17)
    // Trama binaria en cada bio_tick (50 Hz):
    // [0xAA] [0x55] [v_mem_H] [v_mem_L] [i_syn_H] [i_syn_L] [spike] [checksum] [0x0A]
    // =========================================================================
    reg [7:0] tx_byte;
    reg       tx_start;
    wire      tx_busy;

    uart_transceiver #(
        .CLK_FREQ(27000000),
        .BAUD_RATE(115200)
    ) u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .rx(1'b1),
        .tx(uart_tx),
        .rx_byte(),
        .rx_ready(),
        .tx_byte(tx_byte),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

    localparam TELE_IDLE      = 2'd0;
    localparam TELE_SEND      = 2'd1;
    localparam TELE_WAIT_BUSY = 2'd2;
    localparam TELE_WAIT_DONE = 2'd3;

    reg [1:0] tele_state;
    reg [3:0] tele_byte_cnt;

    reg signed [15:0] v_mem_snap;
    reg signed [15:0] i_syn_snap;
    reg               spike_snap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tele_state    <= TELE_IDLE;
            tele_byte_cnt <= 4'd0;
            tx_start      <= 1'b0;
            tx_byte       <= 8'd0;
            v_mem_snap    <= 16'sd0;
            i_syn_snap    <= 16'sd0;
            spike_snap    <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            case (tele_state)
                TELE_IDLE: begin
                    if (bio_tick) begin
                        v_mem_snap    <= v_mem;
                        i_syn_snap    <= i_syn;
                        spike_snap    <= spike;
                        tele_byte_cnt <= 4'd0;
                        tele_state    <= TELE_SEND;
                    end
                end

                TELE_SEND: begin
                    if (!tx_busy) begin
                        case (tele_byte_cnt)
                            4'd0: tx_byte <= 8'hAA; // Sync 1
                            4'd1: tx_byte <= 8'h55; // Sync 2
                            4'd2: tx_byte <= v_mem_snap[15:8];
                            4'd3: tx_byte <= v_mem_snap[7:0];
                            4'd4: tx_byte <= i_syn_snap[15:8];
                            4'd5: tx_byte <= i_syn_snap[7:0];
                            4'd6: tx_byte <= {7'd0, spike_snap};
                            4'd7: tx_byte <= v_mem_snap[15:8] ^ v_mem_snap[7:0] ^
                                             i_syn_snap[15:8] ^ i_syn_snap[7:0] ^
                                             {7'd0, spike_snap}; // Checksum
                            4'd8: tx_byte <= 8'h0A; // EOT ('\n')
                            default: tx_byte <= 8'd0;
                        endcase
                        tx_start   <= 1'b1;
                        tele_state <= TELE_WAIT_BUSY;
                    end
                end

                TELE_WAIT_BUSY: begin
                    if (tx_busy) begin
                        tele_state <= TELE_WAIT_DONE;
                    end
                end

                TELE_WAIT_DONE: begin
                    if (!tx_busy) begin
                        if (tele_byte_cnt < 4'd8) begin
                            tele_byte_cnt <= tele_byte_cnt + 4'd1;
                            tele_state    <= TELE_SEND;
                        end else begin
                            tele_state    <= TELE_IDLE;
                        end
                    end
                end

                default: tele_state <= TELE_IDLE;
            endcase
        end
    end

endmodule
