`timescale 1ns / 1ps
// =============================================================================
// lif_neuron.v - Leaky Integrate-and-Fire (LIF) Neuromorphic Processing Core
// Mathematical Model: Forward Euler Discretization at 50 Hz (dt = 20 ms)
// Features:
//   - Zero-DSP architecture: asymptotic exponential leak via arithmetic shift (>>> 4)
//   - Symmetric saturation arithmetic: 18-bit extended accumulator preventing wrap-around
//   - Rigid hardware clamping: ceiling at +32767, physiological floor at V_MIN (-250)
//   - Absolute refractory period counter (16 biological ticks = 320 ms)
// =============================================================================

module lif_neuron #(
    parameter signed [15:0] V_TH         = 16'sd1000,
    parameter signed [15:0] V_MIN        = -16'sd250, // Physiological hyperpolarization floor
    parameter [4:0]         REFRAC_TICKS = 5'd16      // 16 ticks @ 50 Hz = 320 ms
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               bio_tick,
    input  wire signed [15:0] current_in,
    output reg                spike_out,
    output reg  signed [15:0] v_mem
);

    reg [4:0] refr_cnt;

    // Intermediate datapath registers: leak term, 18-bit extended sum, and next potential
    reg signed [15:0] leak;
    reg signed [17:0] v_sum;
    reg signed [15:0] v_next;

    always @(*) begin
        // Explicit default assignments ensuring zero latch inference
        leak   = 16'sd0;
        v_sum  = 18'sd0;
        v_next = 16'sd0;

        // Symmetric asymptotic leak towards biological resting potential (0_hw = -70 mV):
        // - When v_mem > 0: positive leak decays v_mem downward toward 0.
        // - When v_mem < 0 (hyperpolarized): negative leak pulls v_mem upward toward 0.
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

        // Discrete LIF differential equation with guard bits against overflow/underflow
        v_sum = $signed(v_mem) - $signed(leak) + $signed(current_in);

        // Symmetric Saturation Arithmetic (Hardware Clamping):
        // 1. Upper Ceiling (+32767): Prevents circular overflow to negative on large input bursts
        // 2. Lower Floor (V_MIN = -250): Enforces biological hyperpolarization limit (-75 mV)
        if (v_sum > 18'sd32767) begin
            v_next = 16'sd32767;
        end else if (v_sum < V_MIN) begin
            v_next = V_MIN;
        end else begin
            v_next = v_sum[15:0];
        end
    end

    // Sequential membrane state dynamics synchronously enabled by bio_tick (50 Hz)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_mem     <= 16'sd0;
            spike_out <= 1'b0;
            refr_cnt  <= 5'd0;
        end else begin
            spike_out <= 1'b0; // Default single-cycle synchronous spike pulse
            if (bio_tick) begin
                if (refr_cnt > 5'd0) begin
                    refr_cnt <= refr_cnt - 5'd1;
                    v_mem    <= 16'sd0; // Clamped at resting baseline during refractory period
                end else if (v_next >= V_TH) begin
                    spike_out <= 1'b1;
                    v_mem     <= 16'sd0;
                    refr_cnt  <= REFRAC_TICKS; // Trigger 16-tick (320 ms) refractory lockout
                end else begin
                    v_mem     <= v_next;
                end
            end
        end
    end

endmodule
