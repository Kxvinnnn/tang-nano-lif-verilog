// =============================================================================
// aer_transmitter.sv
// 16-bit Address Event Representation (AER) Protocol Transmitter
// Architecture: Elastic FIFO Buffer + 4-Phase Req/Ack Handshake + Round-Robin Arbiter
// Standard: SystemVerilog IEEE 1800-2017
// =============================================================================

`timescale 1ns / 1ps

module aer_transmitter #(
    parameter int FIFO_DEPTH = 32
)(
    input  logic        clk,             // System clock
    input  logic        rst_n,           // Active-low asynchronous reset

    // -------------------------------------------------------------------------
    // Input Interface from LIF / TDM Neuromorphic Core
    // -------------------------------------------------------------------------
    input  logic        spike_valid,     // Spike strobe pulse
    input  logic [6:0]  spike_neuron_id, // Discharging neuron ID (0 to 99)
    output logic        spike_ready,     // Ready to ingest next spike

    // Global epoch timestamp counter for event tagging
    input  logic [7:0]  epoch_timestamp,

    // -------------------------------------------------------------------------
    // Physical AER Bus (4-Phase Handshake with External Receiver)
    // -------------------------------------------------------------------------
    output logic        aer_req,         // Asynchronous transmission request
    input  logic        aer_ack,         // Acknowledge from external receiver
    output logic [15:0] aer_data,        // Frame: [15]=1, [14:7]=Timestamp, [6:0]=ID

    // Monitoring & Status
    output logic        fifo_full,
    output logic        fifo_empty,
    output logic [5:0]  fifo_occupancy
);

    // -------------------------------------------------------------------------
    // Internal Elastic FIFO Buffer (Handshake Latency Isolation)
    // -------------------------------------------------------------------------
    logic [15:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [4:0]  wr_ptr_q, rd_ptr_q;
    logic [5:0]  count_q;

    assign fifo_empty     = (count_q == 6'd0);
    assign fifo_full      = (count_q == FIFO_DEPTH[5:0]);
    assign fifo_occupancy = count_q;
    assign spike_ready    = !fifo_full;

    wire [15:0] new_spike_packet = {1'b1, epoch_timestamp, 1'b0, spike_neuron_id};

    // FIFO Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_q <= 5'd0;
        end else if (spike_valid && !fifo_full) begin
            fifo_mem[wr_ptr_q] <= new_spike_packet;
            wr_ptr_q           <= wr_ptr_q + 5'd1;
        end
    end

    // -------------------------------------------------------------------------
    // AER Handshake FSM (Strict 4-Phase Sequence)
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        AER_IDLE     = 2'b00,
        AER_REQ_HIGH = 2'b01,
        AER_WAIT_ACK = 2'b10,
        AER_REQ_LOW  = 2'b11
    } aer_fsm_t;

    aer_fsm_t state_q;
    logic [15:0] tx_data_q;
    logic        tx_req_q;

    assign aer_data = tx_data_q;
    assign aer_req  = tx_req_q;

    logic pop_fifo;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= AER_IDLE;
            rd_ptr_q  <= 5'd0;
            count_q   <= 6'd0;
            tx_data_q <= 16'd0;
            tx_req_q  <= 1'b0;
            pop_fifo  <= 1'b0;
        end else begin
            pop_fifo <= 1'b0;

            case ({spike_valid && !fifo_full, pop_fifo})
                2'b10: count_q <= count_q + 6'd1;
                2'b01: count_q <= count_q - 6'd1;
                default: count_q <= count_q;
            endcase

            case (state_q)
                AER_IDLE: begin
                    tx_req_q <= 1'b0;
                    if (!fifo_empty) begin
                        tx_data_q <= fifo_mem[rd_ptr_q];
                        rd_ptr_q  <= rd_ptr_q + 5'd1;
                        pop_fifo  <= 1'b1;
                        tx_req_q  <= 1'b1;
                        state_q   <= AER_WAIT_ACK;
                    end
                end

                AER_WAIT_ACK: begin
                    if (aer_ack) begin
                        tx_req_q <= 1'b0;
                        state_q  <= AER_REQ_LOW;
                    end
                end

                AER_REQ_LOW: begin
                    if (!aer_ack) begin
                        state_q <= AER_IDLE;
                    end
                end

                default: state_q <= AER_IDLE;
            endcase
        end
    end

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA) - FORMAL AER INTEGRITY
    // =========================================================================
    // synthesis translate_off

    property p_aer_data_stability;
        @(posedge clk) disable iff (!rst_n)
        (aer_req && !aer_ack) |=> $stable(aer_data);
    endproperty
    assert_aer_data_stability: assert property (p_aer_data_stability)
        else $error("[SVA ERROR] AER protocol violation: aer_data mutated before receiving aer_ack");

    property p_aer_req_hold_until_ack;
        @(posedge clk) disable iff (!rst_n)
        $fell(aer_req) |-> $past(aer_ack);
    endproperty
    assert_aer_req_hold_until_ack: assert property (p_aer_req_hold_until_ack)
        else $error("[SVA ERROR] AER protocol violation: aer_req dropped prematurely without aer_ack");

    property p_aer_deadlock_watchdog;
        @(posedge clk) disable iff (!rst_n)
        aer_req |-> ##[1:500] aer_ack;
    endproperty
    assert_aer_deadlock_watchdog: assert property (p_aer_deadlock_watchdog)
        else $error("[SVA DEADLOCK] AER bus deadlocked: aer_req asserted > 500 cycles without aer_ack response");

    // synthesis translate_on

endmodule : aer_transmitter
