// =============================================================================
// lif_tdm_core.sv
// LIF Neuromorphic Accelerator Core with Time-Division Multiplexing (TDM)
// Architecture: 100 Neurons emulated via a single 16-bit LIF ALU
// Standard: SystemVerilog IEEE 1800-2017
// =============================================================================

`timescale 1ns / 1ps

package lif_tdm_pkg;
    // Electrophysiological parameters and hardware constants
    localparam int NUM_NEURONS       = 100;
    localparam logic signed [15:0] V_REST  = 16'sd0;      // -70.0 mV base
    localparam logic signed [15:0] V_TH    = 16'sd1000;   // -50.0 mV threshold (20 uV / LSB)
    localparam logic signed [15:0] V_MIN   = -16'sd250;   // -75.0 mV hyperpolarization floor
    localparam logic signed [15:0] V_MAX   = 16'sd32767;  // Dynamic saturation ceiling
    localparam logic [4:0]  REFRACTORY_MAX = 5'd16;       // 16 refractory ticks (320 ms)

    // Typed neuronal state structure
    typedef struct packed {
        logic signed [15:0] v_mem;       // Membrane potential (-250 to +32767)
        logic [4:0]         refractory;  // Refractory period counter
    } neuron_state_t;

    // AER spike event structure
    typedef struct packed {
        logic [6:0] neuron_id;           // Neuron identifier (0 to 99)
        logic [8:0] tag;                 // Timestamp / metadata tag
    } spike_event_t;
endpackage : lif_tdm_pkg

import lif_tdm_pkg::*;

module lif_tdm_core #(
    parameter int N_NEURONS = NUM_NEURONS
)(
    input  logic        clk,             // Core master clock (e.g., 100 MHz)
    input  logic        rst_n,           // Asynchronous active-low reset
    input  logic        enable,          // Processing enable
    input  logic        bio_tick,        // Biological epoch trigger (50 Hz / 20 ms)

    // Dynamic threshold parameters (from CSR registers)
    input  logic signed [15:0] cfg_v_th,
    input  logic [4:0]         cfg_refractory,

    // Synaptic Memory Port A Interface (BRAM Weight Read)
    output logic [13:0]        bram_a_addr,
    output logic               bram_a_en,
    input  logic signed [15:0] bram_a_rdata,

    // Spike event emission interface (To AER Transmitter)
    output logic               spike_valid,
    output logic [6:0]         spike_neuron_id,
    input  logic               spike_ready,

    // Monitoring status
    output logic               tdm_active,
    output logic [6:0]         current_neuron_idx,
    output logic [15:0]        total_spikes_epoch
);

    // -------------------------------------------------------------------------
    // Internal neuronal state memory (100 words)
    // -------------------------------------------------------------------------
    neuron_state_t state_ram [0:N_NEURONS-1];
    neuron_state_t read_state;
    neuron_state_t write_state;

    logic [6:0] state_rd_addr;
    logic [6:0] state_wr_addr;
    logic       state_wr_en;

    // -------------------------------------------------------------------------
    // Máquina de Estados Finitos (FSM) del secuenciador TDM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        TDM_IDLE      = 3'b000,
        TDM_FETCH     = 3'b001,
        TDM_PIPELINE  = 3'b010,
        TDM_EVALUATE  = 3'b011,
        TDM_WRITEBACK = 3'b100,
        TDM_DONE      = 3'b101
    } tdm_state_t;

    tdm_state_t state_q, state_d;

    logic [6:0] neuron_ptr_q, neuron_ptr_d;
    logic [15:0] spike_accum_q, spike_accum_d;

    // Registros de pipeline de la ALU
    logic [6:0]          pipe_id_q;
    neuron_state_t       pipe_state_q;
    logic signed [15:0]  pipe_isyn_q;

    // Señales internas de la ALU LIF de 16 bits
    logic signed [15:0]  v_leak;
    logic signed [17:0]  v_sum_extended;
    logic signed [15:0]  v_clamped;
    logic                alu_spike;
    logic signed [15:0]  v_next;
    logic [4:0]          refractory_next;

    // Asignaciones de puertos de salida
    assign tdm_active         = (state_q != TDM_IDLE);
    assign current_neuron_idx = neuron_ptr_q;
    assign total_spikes_epoch = spike_accum_q;

    assign bram_a_addr = {7'b0, neuron_ptr_q};
    assign bram_a_en   = (state_q == TDM_FETCH || state_q == TDM_PIPELINE);

    // -------------------------------------------------------------------------
    // LIF ALU Combinational Logic (Exact Discrete Mathematics)
    // -------------------------------------------------------------------------
    always_comb begin
        // Asymptotic leak via arithmetic right shift (6.25% decay per tick)
        v_leak = pipe_state_q.v_mem >>> 4;

        // 18-bit signed extended adder for circular overflow prevention
        v_sum_extended = 18'(pipe_state_q.v_mem) - 18'(v_leak) + 18'(pipe_isyn_q);

        // Symmetric hardware clamping: Ceiling at +32767, floor at -250 (Hyperpolarization)
        if (v_sum_extended > 18'(V_MAX)) begin
            v_clamped = V_MAX;
        end else if (v_sum_extended < 18'(V_MIN)) begin
            v_clamped = V_MIN;
        end else begin
            v_clamped = v_sum_extended[15:0];
        end

        // Absolute refractory period dynamics and spike threshold evaluation
        if (pipe_state_q.refractory > 5'd0) begin
            // Active refractory clamp: membrane clamped to resting state (0)
            alu_spike       = 1'b0;
            v_next          = V_REST;
            refractory_next = pipe_state_q.refractory - 5'd1;
        end else begin
            // Evaluate against configured spike threshold
            if (v_clamped >= cfg_v_th) begin
                alu_spike       = 1'b1;
                v_next          = V_REST;
                refractory_next = (cfg_refractory != 5'd0) ? cfg_refractory : REFRACTORY_MAX;
            end else begin
                alu_spike       = 1'b0;
                v_next          = v_clamped;
                refractory_next = 5'd0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // FSM y Secuenciador TDM
    // -------------------------------------------------------------------------
    always_comb begin
        state_d       = state_q;
        neuron_ptr_d  = neuron_ptr_q;
        spike_accum_d = spike_accum_q;

        state_rd_addr = neuron_ptr_q;
        state_wr_addr = pipe_id_q;
        state_wr_en   = 1'b0;
        write_state   = '{v_mem: V_REST, refractory: 5'd0};

        case (state_q)
            TDM_IDLE: begin
                neuron_ptr_d = 7'd0;
                if (enable && bio_tick) begin
                    spike_accum_d = 16'd0;
                    state_d       = TDM_FETCH;
                end
            end

            TDM_FETCH: begin
                // Read state from internal RAM and weight from BRAM Port A
                state_rd_addr = neuron_ptr_q;
                state_d       = TDM_PIPELINE;
            end

            TDM_PIPELINE: begin
                // Wait 1 cycle for BRAM and state RAM to output stable synchronous data
                state_d = TDM_EVALUATE;
            end

            TDM_EVALUATE: begin
                // ALU computes v_next, refractory_next, and alu_spike
                state_d = TDM_WRITEBACK;
            end

            TDM_WRITEBACK: begin
                // Write back evaluated state
                state_wr_en = 1'b1;
                state_wr_addr = pipe_id_q;
                write_state = '{v_mem: v_next, refractory: refractory_next};

                if (alu_spike) begin
                    spike_accum_d = spike_accum_q + 1'b1;
                end

                // Advance to next neuron or complete TDM epoch
                if (neuron_ptr_q >= (N_NEURONS - 1)) begin
                    state_d = TDM_DONE;
                end else begin
                    neuron_ptr_d = neuron_ptr_q + 7'd1;
                    state_d      = TDM_FETCH;
                end
            end

            TDM_DONE: begin
                state_d = TDM_IDLE;
            end

            default: state_d = TDM_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Synchronous Registers and Spike Emission
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q         <= TDM_IDLE;
            neuron_ptr_q    <= 7'd0;
            spike_accum_q   <= 16'd0;
            pipe_id_q       <= 7'd0;
            pipe_state_q    <= '{v_mem: V_REST, refractory: 5'd0};
            pipe_isyn_q     <= 16'sd0;
            spike_valid     <= 1'b0;
            spike_neuron_id <= 7'd0;
        end else begin
            state_q       <= state_d;
            neuron_ptr_q  <= neuron_ptr_d;
            spike_accum_q <= spike_accum_d;

            // Read pipeline
            if (state_q == TDM_PIPELINE) begin
                pipe_id_q    <= neuron_ptr_q;
                pipe_state_q <= state_ram[neuron_ptr_q];
                pipe_isyn_q  <= bram_a_rdata;
            end

            // Write to state RAM
            if (state_wr_en) begin
                state_ram[state_wr_addr] <= write_state;
            end

            // Generate spike strobe towards AER
            if (state_q == TDM_WRITEBACK && alu_spike) begin
                spike_valid     <= 1'b1;
                spike_neuron_id <= pipe_id_q;
            end else if (spike_ready) begin
                spike_valid <= 1'b0;
            end
        end
    end

    // Explicit state initialization for 100 neurons
    initial begin
        for (int i = 0; i < N_NEURONS; i++) begin
            state_ram[i] = '{v_mem: V_REST, refractory: 5'd0};
        end
    end

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA) - FORMAL INTEGRATED VERIFICATION
    // =========================================================================
    // synthesis translate_off

    // 1. Boundary Invariant: TDM pointer must never exceed N_NEURONS limit
    property p_neuron_ptr_bounded;
        @(posedge clk) disable iff (!rst_n)
        neuron_ptr_q < N_NEURONS;
    endproperty
    assert_neuron_ptr_bounded: assert property (p_neuron_ptr_bounded)
        else $fatal(1, "[SVA CRITICAL] neuron_ptr_q exceeded N_NEURONS limit: %0d >= %0d", neuron_ptr_q, N_NEURONS);

    // 2. Arithmetic Clamping Integrity: v_mem written to memory must strictly respect [-250, +32767]
    property p_v_mem_clamped_range;
        @(posedge clk) disable iff (!rst_n)
        state_wr_en |-> (write_state.v_mem >= V_MIN && write_state.v_mem <= V_MAX);
    endproperty
    assert_v_mem_clamped_range: assert property (p_v_mem_clamped_range)
        else $error("[SVA ERROR] write_state.v_mem out of saturation bounds: %0d", write_state.v_mem);

    // 3. Post-Spike Determinism: Spike emission mandates reset to V_REST and refractory reload
    property p_spike_reset_determinism;
        @(posedge clk) disable iff (!rst_n)
        (state_q == TDM_WRITEBACK && alu_spike) |-> (write_state.v_mem == V_REST && write_state.refractory == cfg_refractory);
    endproperty
    assert_spike_reset_determinism: assert property (p_spike_reset_determinism)
        else $error("[SVA ERROR] Spike emitted without clamping at V_REST or valid refractory reload.");

    // synthesis translate_on

endmodule : lif_tdm_core
