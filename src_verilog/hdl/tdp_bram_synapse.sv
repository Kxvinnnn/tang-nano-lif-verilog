// =============================================================================
// tdp_bram_synapse.sv
// True Dual-Port BRAM Memory for Synaptic Matrix (GW1NR-9C)
// Port A: Synchronous read for TDM core (100 MHz)
// Port B: Synchronous Read/Write for CSR runtime reconfiguration bus
// =============================================================================

`timescale 1ns / 1ps

module tdp_bram_synapse #(
    parameter int ADDR_WIDTH = 14,
    parameter int DATA_WIDTH = 16,
    parameter int DEPTH      = 1024,
    parameter     INIT_FILE  = "data/synaptic_weights.hex"
)(
    // Port A: TDM Core (Read)
    input  logic                  clk_a,
    input  logic                  en_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    output logic [DATA_WIDTH-1:0] rdata_a,

    // Port B: CSR Bus (Read / Hot Write)
    input  logic                  clk_b,
    input  logic                  en_b,
    input  logic                  we_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic [DATA_WIDTH-1:0] wdata_b,
    output logic [DATA_WIDTH-1:0] rdata_b
);

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk_a) begin
        if (en_a) begin
            rdata_a <= mem[addr_a];
        end
    end

    always_ff @(posedge clk_b) begin
        if (en_b) begin
            if (we_b) begin
                mem[addr_b] <= wdata_b;
            end
            rdata_b <= mem[addr_b];
        end
    end

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 16'sd0;
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

endmodule : tdp_bram_synapse
