`timescale 1ns / 1ps
// =============================================================================
// button_debouncer.v - Industrial-Grade Physical Signal Conditioner
// Topology:
//   - Stage 1: 2-FF Synchronizer chain mitigating asynchronous metastability
//   - Stage 2: Parameterizable temporal hysteresis debounce counter
// Compliance: Zero reliance on 'initial' blocks, deterministic reset (AASD)
// =============================================================================

module button_debouncer #(
    parameter CLK_FREQ         = 27_000_000,
    parameter DEBOUNCE_TIME_MS = 20
)(
    input  wire clk,
    input  wire rst_n,          // Active-low synchronous/asynchronous reset
    input  wire btn_async_in,   // Raw asynchronous mechanical input (active-low with pull-up)
    output reg  btn_clean_out   // Clean, debounced level (active-high on press)
);
    localparam COUNT_MAX = (CLK_FREQ / 1000) * DEBOUNCE_TIME_MS;
    localparam CNT_WIDTH = (COUNT_MAX > 1) ? $clog2(COUNT_MAX) : 1;
    
    // Stage 1: Metastability Mitigation (Dual Flip-Flop Synchronizer)
    // S1/S2 pushbuttons on Tang Nano 9K have hardware pull-ups (idle high = 1'b1)
    reg sync_0;
    reg sync_1;

    // Stage 2: Mechanical Bounce Filter with Temporal Integration Hysteresis
    reg [CNT_WIDTH-1:0] counter;
    reg                 state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0        <= 1'b1; // Idle state with active pull-up
            sync_1        <= 1'b1;
            counter       <= {CNT_WIDTH{1'b0}};
            state         <= 1'b1;
            btn_clean_out <= 1'b0; // Inactive in resting state
        end else begin
            // 2-FF synchronizer sampling
            sync_0 <= btn_async_in;
            sync_1 <= sync_0;

            if (sync_1 != state) begin
                if (counter >= COUNT_MAX - 1) begin
                    state         <= sync_1;
                    counter       <= {CNT_WIDTH{1'b0}};
                    btn_clean_out <= ~sync_1; // Active-high when pressed (physical logic 0)
                end else begin
                    counter <= counter + 1'b1;
                end
            end else begin
                counter <= {CNT_WIDTH{1'b0}};
            end
        end
    end

endmodule
