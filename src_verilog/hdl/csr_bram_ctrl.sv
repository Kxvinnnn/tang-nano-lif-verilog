// =============================================================================
// csr_bram_ctrl.sv
// Controlador de Bus Esclavo CSR (Control and Status Registers) y Puerto B BRAM
// Habilita reconfiguración dinámica de pesos sinápticos y parámetros en caliente
// Estándar: SystemVerilog IEEE 1800-2017
// =============================================================================

`timescale 1ns / 1ps

module csr_bram_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------------
    // Interfaz Esclava CSR de 32 bits (Memoria Mapeada)
    // -------------------------------------------------------------------------
    input  logic [31:0] csr_addr,        // Dirección de 32 bits
    input  logic [31:0] csr_wdata,       // Datos de escritura
    input  logic        csr_write,       // 1 = Escritura, 0 = Lectura
    input  logic        csr_valid,       // Solicitud de transacción válida
    output logic [31:0] csr_rdata,       // Datos de lectura
    output logic        csr_ready,       // Acknowledge / Terminación de ciclo

    // -------------------------------------------------------------------------
    // Señales de Control y Configuración hacia el Núcleo TDM
    // -------------------------------------------------------------------------
    output logic        core_en,
    output logic        core_soft_rst,
    output logic signed [15:0] cfg_v_th,
    output logic [4:0]  cfg_refractory,
    input  logic        tdm_active,
    input  logic [15:0] spike_count_in,

    // -------------------------------------------------------------------------
    // Interfaz Puerto B de True Dual-Port BRAM (Matriz de Pesos)
    // -------------------------------------------------------------------------
    output logic [13:0]        bram_b_addr,
    output logic signed [15:0] bram_b_wdata,
    output logic               bram_b_we,
    output logic               bram_b_en,
    input  logic signed [15:0] bram_b_rdata
);

    // Mapa de Registros de Control
    localparam logic [31:0] ADDR_CTRL         = 32'h0000_0000;
    localparam logic [31:0] ADDR_STATUS       = 32'h0000_0004;
    localparam logic [31:0] ADDR_CFG_TH       = 32'h0000_0008;
    localparam logic [31:0] ADDR_CFG_REF      = 32'h0000_000C;
    localparam logic [31:0] BRAM_WINDOW_BASE  = 32'h0000_1000;
    localparam logic [31:0] BRAM_WINDOW_LIMIT = 32'h0000_5000;

    // Registros internos
    logic        reg_en_q;
    logic        reg_soft_rst_q;
    logic signed [15:0] reg_v_th_q;
    logic [4:0]  reg_refractory_q;

    // Asignación de salidas de control
    assign core_en         = reg_en_q;
    assign core_soft_rst   = reg_soft_rst_q;
    assign cfg_v_th        = reg_v_th_q;
    assign cfg_refractory  = reg_refractory_q;

    // Detección de ventana de acceso a BRAM
    logic is_bram_access;
    assign is_bram_access = (csr_addr >= BRAM_WINDOW_BASE && csr_addr < BRAM_WINDOW_LIMIT);

    // Decodificación de dirección BRAM (desplazamiento relativo de palabra de 16 bits)
    assign bram_b_addr  = csr_addr[14:1];
    assign bram_b_wdata = csr_wdata[15:0];
    assign bram_b_we    = csr_valid && csr_write && is_bram_access;
    assign bram_b_en    = csr_valid && is_bram_access;

    // FSM de control de latencia de bus CSR (Handshake de 1 ciclo)
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
            reg_en_q         <= 1'b1;         // Habilitado por defecto
            reg_soft_rst_q   <= 1'b0;
            reg_v_th_q       <= 16'sd1000;    // 1000_hw (-50.0 mV)
            reg_refractory_q <= 5'd16;        // 16 ticks por defecto
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
        else $error("[SVA ERROR] Transacción de bus CSR no completada en el tiempo límite.");

    // synthesis translate_on

endmodule : csr_bram_ctrl
