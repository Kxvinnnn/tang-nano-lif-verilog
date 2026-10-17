// =============================================================================
// csr_bram_ctrl.sv
// Control and Status Registers (CSR) Slave Bus Controller & BRAM Port B Arbiter
// Enables dynamic runtime reconfiguration of synaptic weights and LIF parameters
// Standard: SystemVerilog IEEE 1800-2017
// =============================================================================

`timescale 1ns / 1ps

module csr_bram_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------------
    // 32-bit Memory-Mapped CSR Slave Interface
    // -------------------------------------------------------------------------
    input  logic [31:0] csr_addr,        // 32-bit address
    input  logic [31:0] csr_wdata,       // Write data
    input  logic        csr_write,       // 1 = Write, 0 = Read
    input  logic        csr_valid,       // Valid transaction request
    output logic [31:0] csr_rdata,       // Read data
    output logic        csr_ready,       // Cycle acknowledge / termination

    // -------------------------------------------------------------------------
    // Control & Configuration Signals to TDM Core
    // -------------------------------------------------------------------------
    output logic        core_en,
    output logic        core_soft_rst,
    output logic signed [15:0] cfg_v_th,
    output logic [4:0]  cfg_refractory,
    input  logic        tdm_active,
    input  logic [15:0] spike_count_in,

    // -------------------------------------------------------------------------
    // True Dual-Port BRAM Port B Interface (Synaptic Weight Matrix)
    // -------------------------------------------------------------------------
    output logic [13:0]        bram_b_addr,
    output logic signed [15:0] bram_b_wdata,
    output logic               bram_b_we,
    output logic               bram_b_en,
    input  logic signed [15:0] bram_b_rdata
);

    // Control Register Memory Map
    localparam logic [31:0] ADDR_CTRL         = 32'h0000_0000;
    localparam logic [31:0] ADDR_STATUS       = 32'h0000_0004;
    localparam logic [31:0] ADDR_CFG_TH       = 32'h0000_0008;
    localparam logic [31:0] ADDR_CFG_REF      = 32'h0000_000C;
    localparam logic [31:0] BRAM_WINDOW_BASE  = 32'h0000_1000;
    localparam logic [31:0] BRAM_WINDOW_LIMIT = 32'h0000_5000;

    // Internal Configuration Registers
    logic        reg_en_q;
    logic        reg_soft_rst_q;
    logic signed [15:0] reg_v_th_q;
    logic [4:0]  reg_refractory_q;

    // Control Output Assignments
    assign core_en         = reg_en_q;
    assign core_soft_rst   = reg_soft_rst_q;
    assign cfg_v_th        = reg_v_th_q;
    assign cfg_refractory  = reg_refractory_q;

    // BRAM access window detection
    logic is_bram_access;
    assign is_bram_access = (csr_addr >= BRAM_WINDOW_BASE && csr_addr < BRAM_WINDOW_LIMIT);

    // BRAM address decoding (relative 16-bit word offset)
    assign bram_b_addr  = csr_addr[14:1];
    assign bram_b_wdata = csr_wdata[15:0];
    assign bram_b_we    = csr_valid && csr_write && is_bram_access;
    assign bram_b_en    = csr_valid && is_bram_access;

    // CSR bus latency control FSM (1-cycle Handshake)
    typedef enum logic [1:0] {
        CSR_IDLE   = 2'b00,
        CSR_ACCESS = 2'b01,
        CSR_ACK    = 2'b10
    } csr_state_t;

    csr_state_t state_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q          <= CSR_IDLE;
            csr_ready        <= 1'b0;
            csr_rdata        <= 32'd0;
            reg_en_q         <= 1'b1;         // Enabled by default
            reg_soft_rst_q   <= 1'b0;
            reg_v_th_q       <= 16'sd1000;    // 1000_hw (-50.0 mV)
            reg_refractory_q <= 5'd16;        // 16 ticks by default
        end else begin
            csr_ready <= 1'b0;

            case (state_q)
                CSR_IDLE: begin
                    if (csr_valid) begin
                        if (is_bram_access) begin
                            state_q <= CSR_ACCESS;
                        end else begin
                            csr_ready <= 1'b1;
                            if (csr_write) begin
                                case (csr_addr)
                                    ADDR_CTRL: begin
                                        reg_en_q       <= csr_wdata[0];
                                        reg_soft_rst_q <= csr_wdata[1];
                                    end
                                    ADDR_CFG_TH: begin
                                        reg_v_th_q <= csr_wdata[15:0];
                                    end
                                    ADDR_CFG_REF: begin
                                        reg_refractory_q <= csr_wdata[4:0];
                                    end
                                    default: ;
                                endcase
                            end else begin
                                case (csr_addr)
                                    ADDR_CTRL:    csr_rdata <= {30'd0, reg_soft_rst_q, reg_en_q};
                                    ADDR_STATUS:  csr_rdata <= {16'd0, spike_count_in[7:0], 7'd0, tdm_active};
                                    ADDR_CFG_TH:  csr_rdata <= {16'd0, reg_v_th_q};
                                    ADDR_CFG_REF: csr_rdata <= {27'd0, reg_refractory_q};
                                    default:      csr_rdata <= 32'hDEAD_BEEF;
                                endcase
                            end
                        end
                    end
                end

                CSR_ACCESS: begin
                    csr_ready <= 1'b1;
                    if (!csr_write) begin
                        csr_rdata <= {16'd0, bram_b_rdata};
                    end
                    state_q <= CSR_IDLE;
                end

                default: state_q <= CSR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA)
    // =========================================================================
    // synthesis translate_off

    property p_csr_handshake_completion;
        @(posedge clk) disable iff (!rst_n)
        csr_valid |-> ##[1:2] csr_ready;
    endproperty
    assert_csr_handshake_completion: assert property (p_csr_handshake_completion)
        else $error("[SVA ERROR] CSR bus transaction not completed within timeout limit.");

    // synthesis translate_on

endmodule : csr_bram_ctrl
