`timescale 1ns / 1ps
module debounce_sync (
    input  wire clk,
    input  wire rst_n,
    input  wire btn_in,
    output reg  btn_out
);
    // Sincronizador de 2 etapas contra metaestabilidad
    reg sync_0;
    reg sync_1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0 <= 1'b1;
            sync_1 <= 1'b1;
        end else begin
            sync_0 <= btn_in;
            sync_1 <= sync_0;
        end
    end

    // Contador de antirrebote (~10ms a 27MHz -> 270,000 ciclos)
    reg [18:0] cnt;
    reg debounced_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 19'd0;
            debounced_state <= 1'b1;
            btn_out <= 1'b1;
        end else begin
            if (sync_1 != debounced_state) begin
                cnt <= cnt + 19'd1;
                if (cnt >= 19'd270000) begin
                    debounced_state <= sync_1;
                    btn_out <= sync_1;
                    cnt <= 19'd0;
                end
            end else begin
                cnt <= 19'd0;
                btn_out <= debounced_state;
            end
        end
    end
endmodule
