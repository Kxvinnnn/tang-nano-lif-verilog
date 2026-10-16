// =============================================================================
// top_tdm_snn.sv
// Top-Level del Sistema Acelerador Neuromórfico TDM de 100 Neuronas
// Integra: lif_tdm_core + tdp_bram_synapse + csr_bram_ctrl + aer_transmitter
// Estándar: SystemVerilog IEEE 1800-2017
// =============================================================================

`timescale 1ns / 1ps

module top_tdm_snn #(
    parameter int NUM_NEURONS = 100
)(
    input  logic        clk,             // Reloj maestro del sistema (ej. 27 MHz o 100 MHz)
    input  logic        rst_n,           // Reset físico activo en bajo

    // Entrada de tick biológico externo (o generado internamente a 50 Hz)
    input  logic        bio_tick_in,
    input  logic        bio_tick_ext_sel,

    // -------------------------------------------------------------------------
    // Bus Esclavo CSR (Configuración y Escritura de Pesos en Caliente)
    // -------------------------------------------------------------------------
    input  logic [31:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic        csr_write,
    input  logic        csr_valid,
    output logic [31:0] csr_rdata,
    output logic        csr_ready,

    // -------------------------------------------------------------------------
    // Bus Asíncrono AER de 16 bits (Emisión de Eventos de Disparo)
    // -------------------------------------------------------------------------
    output logic        aer_req,
    input  logic        aer_ack,
    output logic [15:0] aer_data,

    // Indicadores de Estado y Monitoreo Físico
    output logic        tdm_active_led,
    output logic        spike_activity_led,
    output logic [15:0] total_spikes_epoch
);

    // -------------------------------------------------------------------------
    // Prescaler Interno de 50 Hz (20.0 ms) a 27.0 MHz
    // -------------------------------------------------------------------------
    logic [19:0] bio_cnt;
    logic        bio_tick_internal;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bio_cnt           <= 20'd0;
            bio_tick_internal <= 1'b0;
        end else begin
            if (bio_cnt >= 20'd539_999) begin
                bio_cnt           <= 20'd0;
                bio_tick_internal <= 1'b1;
            end else begin
                bio_cnt           <= bio_cnt + 20'd1;
                bio_tick_internal <= 1'b0;
            end
        end
    end

    wire bio_tick_effective = bio_tick_ext_sel ? bio_tick_in : bio_tick_internal;

    // -------------------------------------------------------------------------
    // Contador de Épocas para Marca de Tiempo AER
    // -------------------------------------------------------------------------
    logic [7:0] epoch_counter;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch_counter <= 8'd0;
        end else if (bio_tick_effective) begin
            epoch_counter <= epoch_counter + 8'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Interconexiones entre Módulos
    // -------------------------------------------------------------------------
    logic        core_en;
    logic        core_soft_rst;
    logic signed [15:0] cfg_v_th;
    logic [4:0]  cfg_refractory;
    logic        tdm_active;

    // BRAM Puerto A (TDM Core)
    logic [13:0]        bram_a_addr;
    logic               bram_a_en;
    logic signed [15:0] bram_a_rdata;

    // BRAM Puerto B (CSR Bus)
    logic [13:0]        bram_b_addr;
    logic signed [15:0] bram_b_wdata;
    logic               bram_b_we;
    logic               bram_b_en;
    logic signed [15:0] bram_b_rdata;

    // Interfaz Spike Core -> AER Transmitter
    logic        core_spike_valid;
    logic [6:0]  core_spike_neuron_id;
    logic        aer_spike_ready;

    // Reset compuesto
    wire effective_rst_n = rst_n && (!core_soft_rst);

    // -------------------------------------------------------------------------
    // Instanciación del Controlador CSR
    // -------------------------------------------------------------------------
    csr_bram_ctrl u_csr_ctrl (
        .clk             (clk),
        .rst_n           (effective_rst_n),
        .csr_addr        (csr_addr),
        .csr_wdata       (csr_wdata),
        .csr_write       (csr_write),
        .csr_valid       (csr_valid),
        .csr_rdata       (csr_rdata),
        .csr_ready       (csr_ready),
        .core_en         (core_en),
        .core_soft_rst   (core_soft_rst),
        .cfg_v_th        (cfg_v_th),
        .cfg_refractory  (cfg_refractory),
        .tdm_active      (tdm_active),
        .spike_count_in  (total_spikes_epoch),
        .bram_b_addr     (bram_b_addr),
        .bram_b_wdata    (bram_b_wdata),
        .bram_b_we       (bram_b_we),
        .bram_b_en       (bram_b_en),
        .bram_b_rdata    (bram_b_rdata)
    );

    // -------------------------------------------------------------------------
    // Instanciación de la True Dual-Port BRAM
    // -------------------------------------------------------------------------
    tdp_bram_synapse #(
        .ADDR_WIDTH (14),
        .DATA_WIDTH (16),
        .DEPTH      (1024),
        .INIT_FILE  ("data/pesos_sinapticos.hex")
    ) u_bram (
        .clk_a   (clk),
        .en_a    (bram_a_en),
        .addr_a  (bram_a_addr),
        .rdata_a (bram_a_rdata),
        .clk_b   (clk),
        .en_b    (bram_b_en),
        .we_b    (bram_b_we),
        .addr_b  (bram_b_addr),
        .wdata_b (bram_b_wdata),
        .rdata_b (bram_b_rdata)
    );

    // -------------------------------------------------------------------------
    // Instanciación del Núcleo TDM LIF (100 Neuronas)
    // -------------------------------------------------------------------------
    lif_tdm_core #(
        .N_NEURONS (NUM_NEURONS)
    ) u_lif_core (
        .clk                (clk),
        .rst_n              (effective_rst_n),
        .enable             (core_en),
        .bio_tick           (bio_tick_effective),
        .cfg_v_th           (cfg_v_th),
        .cfg_refractory     (cfg_refractory),
        .bram_a_addr        (bram_a_addr),
        .bram_a_en          (bram_a_en),
        .bram_a_rdata       (bram_a_rdata),
        .spike_valid        (core_spike_valid),
        .spike_neuron_id    (core_spike_neuron_id),
        .spike_ready        (aer_spike_ready),
        .tdm_active         (tdm_active),
        .current_neuron_idx (),
        .total_spikes_epoch (total_spikes_epoch)
    );

    // -------------------------------------------------------------------------
    // Instanciación del Transmisor AER de 16 bits
    // -------------------------------------------------------------------------
    aer_transmitter #(
        .FIFO_DEPTH (32)
    ) u_aer_tx (
        .clk             (clk),
        .rst_n           (effective_rst_n),
        .spike_valid     (core_spike_valid),
        .spike_neuron_id (core_spike_neuron_id),
        .spike_ready     (aer_spike_ready),
        .epoch_timestamp (epoch_counter),
        .aer_req         (aer_req),
        .aer_ack         (aer_ack),
        .aer_data        (aer_data),
        .fifo_full       (),
        .fifo_empty      (),
        .fifo_occupancy  ()
    );

    // Asignación de LEDs de actividad
    assign tdm_active_led     = tdm_active;
    assign spike_activity_led = core_spike_valid;

endmodule : top_tdm_snn
