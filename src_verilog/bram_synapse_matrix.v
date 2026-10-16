`timescale 1ns / 1ps
// =============================================================================
// bram_synapse_matrix.v - Matriz BRAM de Pesos Sinápticos (GW1NR-9C)
// Características: Salida registrada protegida contra direcciones fuera de rango,
//                  reset síncrono para anular estados flotantes ('x'/'z').
// =============================================================================

module bram_synapse_matrix #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 16,
    parameter MEM_SIZE   = 8,
    parameter HEX_FILE   = "data/pesos_sinapticos.hex"
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          we,
    input  wire [ADDR_WIDTH-1:0]         addr,
    input  wire signed [DATA_WIDTH-1:0]  din,
    output reg  signed [DATA_WIDTH-1:0]  dout
);

    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] ram [0:MEM_SIZE-1];

    // Carga de coeficientes estáticos en fase de configuración de la FPGA
    initial begin
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, ram);
        end
    end

    // Acceso síncrono con tolerancia cero a direcciones fuera de rango
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= {DATA_WIDTH{1'b0}};
        end else begin
            if (we && (addr < MEM_SIZE)) begin
                ram[addr] <= din;
            end

            // Protección de límite: Evita que lecturas fuera de rango devuelvan 'x'
            if (addr < MEM_SIZE) begin
                dout <= ram[addr];
            end else begin
                dout <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
