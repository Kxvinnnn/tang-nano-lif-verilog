`timescale 1ns / 1ps
// =============================================================================
// bram_synapse_matrix.v - Block RAM Synaptic Weight Matrix (Gowin GW1NR-9C)
// Architecture Features:
//   - Synthesized into dedicated embedded BSRAM via (* ram_style = "block" *)
//   - Synchronously registered output with out-of-range bounds protection
//   - Zero-unknown ('X'/'Z') guarantee under reset and unmapped addresses
// =============================================================================

module bram_synapse_matrix #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 16,
    parameter MEM_SIZE   = 8,
    parameter HEX_FILE   = "data/synaptic_weights.hex"
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          we,
    input  wire [ADDR_WIDTH-1:0]         addr,
    input  wire signed [DATA_WIDTH-1:0]  din,
    output reg  signed [DATA_WIDTH-1:0]  dout
);

    // Force synthesis into dedicated Gowin BSRAM blocks rather than distributed LUTs
    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] ram [0:MEM_SIZE-1];

    // Static coefficient preload during FPGA configuration phase
    initial begin
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, ram);
        end
    end

    // Synchronous memory access with zero tolerance to out-of-bounds addressing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= {DATA_WIDTH{1'b0}};
        end else begin
            if (we && (addr < MEM_SIZE)) begin
                ram[addr] <= din;
            end

            // Boundary protection: clamp unmapped address reads strictly to zero (no 'X'/'Z')
            if (addr < MEM_SIZE) begin
                dout <= ram[addr];
            end else begin
                dout <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
