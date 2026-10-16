`timescale 1ns / 1ps

module lif_neuron #(
    parameter signed [15:0] V_TH         = 16'sd1000,
    parameter signed [15:0] V_MIN        = -16'sd250, // Límite de hiperpolarización biológica
    parameter [4:0]         REFRAC_TICKS = 5'd16      // 16 ticks a 50 Hz = 320 ms
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               bio_tick,
    input  wire signed [15:0] current_in,
    output reg                spike_out,
    output reg  signed [15:0] v_mem
);

    reg [4:0] refr_cnt;

    // Fuga (leak), suma intermedia extendida y siguiente potencial (v_next)
    reg signed [15:0] leak;
    reg signed [17:0] v_sum;
    reg signed [15:0] v_next;

    always @(*) begin
        // Fuga natural hacia el potencial de reposo (0):
        // Para v_mem > 0: leak positivo hace decrecer v_mem hacia 0.
        // Para v_mem < 0 (hiperpolarización): leak negativo hace crecer v_mem hacia 0.
        if (v_mem > 16'sd0) begin
            if ((v_mem >>> 4) == 16'sd0)
                leak = 16'sd1;
            else
                leak = v_mem >>> 4;
        end else if (v_mem < 16'sd0) begin
            if ((v_mem >>> 4) == 16'sd0)
                leak = -16'sd1;
            else
                leak = v_mem >>> 4;
        end else begin
            leak = 16'sd0;
        end

        // Ecuación diferencial LIF con bits de guarda contra overflow/underflow
        v_sum = $signed(v_mem) - $signed(leak) + $signed(current_in);

        // Aritmética de saturación simétrica (Clamping Hardware):
        // 1. Techo: Evita desbordamiento cíclico a negativo ante ráfagas masivas
        // 2. Piso: Limita la hiperpolarización biológica a V_MIN (-250)
        if (v_sum > 18'sd32767) begin
            v_next = 16'sd32767;
        end else if (v_sum < V_MIN) begin
            v_next = V_MIN;
        end else begin
            v_next = v_sum[15:0];
        end
    end

    // Dinámica secuencial continua gobernada incondicionalmente por bio_tick
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_mem     <= 16'sd0;
            spike_out <= 1'b0;
            refr_cnt  <= 5'd0;
        end else begin
            spike_out <= 1'b0; // Pulso síncrono de 1 ciclo clk
            if (bio_tick) begin
                if (refr_cnt > 5'd0) begin
                    refr_cnt <= refr_cnt - 5'd1;
                    v_mem    <= 16'sd0; // Forzado estricto en 0 durante periodo refractario
                end else if (v_next >= V_TH) begin
                    spike_out <= 1'b1;
                    v_mem     <= 16'sd0;
                    refr_cnt  <= REFRAC_TICKS; // Inicia 16 ticks (320 ms) refractarios
                end else begin
                    v_mem     <= v_next;
                end
            end
        end
    end

endmodule
