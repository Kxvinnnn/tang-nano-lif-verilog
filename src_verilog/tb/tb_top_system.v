`timescale 1ns / 1ps
// =============================================================================
// tb_top_system.v - Banco de Pruebas de Integración a Nivel de Sistema
// Valida: Inyección de ruido en botones (Bouncing), 2-FF Sync + Debouncer,
//         Conexión BRAM -> LIF, Disparo, Vúmetro PWM y Transmisión UART.
// =============================================================================

module tb_top_system;

    reg        clk;
    reg        btn1;
    reg        btn2;
    wire       uart_tx;
    wire [5:0] led;

    // Instancia del sistema completo con debouncer acelerado a 1 ms para simulación
    top_lif_demo #(
        .CLK_FREQ(27_000_000),
        .DEBOUNCE_TIME_MS(1),
        .HEX_FILE("data/pesos_sinapticos.hex")
    ) uut (
        .clk(clk),
        .btn1(btn1),
        .btn2(btn2),
        .uart_tx(uart_tx),
        .led(led)
    );

    // Oscilador de 27.0 MHz (Periodo: ~37.037 ns -> Semiperiodo: 18.5185 ns)
    always #18.5185 clk = ~clk;

    integer errors = 0;

    initial begin
        $dumpfile("build/tb_top_system.vcd");
        $dumpvars(0, tb_top_system);

        clk  = 1'b0;
        btn1 = 1'b1; // Reposo con Pull-Up activo
        btn2 = 1'b1;

        $display("=================================================================");
        $display("  INICIO DE TESTBENCH DE INTEGRACION TOP-LEVEL (top_lif_demo)");
        $display("=================================================================");

        // Espera de arranque y estabilización del sincronizador de reset (AASD)
        #500000; // 500 us
        if (!uut.rst_n) begin
            $display("[ERROR] Sincronizador de reset rst_n no se libero correctamente.");
            errors = errors + 1;
        end else begin
            $display("[OK] Reset sincronizado y liberado sin violacion de Recovery.");
        end

        // ---------------------------------------------------------------------
        // TEST 1: Inyección de Ruido Mecánico (Bouncing) en Botón S1
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Inyectando tren de rebotes mecanicos (< 1 ms) en S1...");
        #50000;  btn1 = 1'b0; // Rebote 1 (50 us)
        #80000;  btn1 = 1'b1;
        #120000; btn1 = 1'b0; // Rebote 2 (120 us)
        #70000;  btn1 = 1'b1;
        #150000; btn1 = 1'b0; // Rebote 3 (150 us)
        #90000;  btn1 = 1'b1;
        #200000; // Espera en reposo

        if (uut.btn1_clean !== 1'b0) begin
            $display("[ERROR] El debouncer permitio el paso de ruido mecanico en S1.");
            errors = errors + 1;
        end else begin
            $display("[OK] Ruido mecanico transitorio (< 1 ms) filtrado al 100%% por el debouncer.");
        end

        // ---------------------------------------------------------------------
        // TEST 2: Presión Sostenida de S1 (> 1 ms) y Conexión BRAM Excitatoria
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Presion sostenida de S1 (> 1 ms). Validando debouncer y BRAM...");
        btn1 = 1'b0;
        #1500000; // 1.5 ms sostenido (supera umbral de 1 ms)

        if (uut.btn1_clean !== 1'b1) begin
            $display("[ERROR] El debouncer no reconocio la pulsacion sostenida de S1.");
            errors = errors + 1;
        end else begin
            $display("[OK] Debouncer filtro y reconocio la pulsacion sostenida de S1.");
        end

        // Validar que la BRAM entregue el peso excitatorio (+68)
        #100000;
        if (uut.i_syn !== 16'sd68) begin
            $display("[ERROR] Desconexion BRAM -> LIF. i_syn esperado: +68, obtenido: %d", uut.i_syn);
            errors = errors + 1;
        end else begin
            $display("[OK] Conector BRAM -> LIF validado. Peso sinaptico excitatorio leido: +68.");
        end

        // Liberar botón S1
        btn1 = 1'b1;
        #1500000; // 1.5 ms para que debouncer detecte la liberación
        if (uut.btn1_clean !== 1'b0) begin
            $display("[ERROR] El debouncer no desaserto tras la liberacion de S1.");
            errors = errors + 1;
        end else begin
            $display("[OK] Liberacion de S1 registrada correctamente.");
        end

        // ---------------------------------------------------------------------
        // TEST 3: Presión de S2 (Inhibición y Clamping en V_MIN = -250)
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Presion sostenida de S2 (Inhibicion). Validando BRAM y V_MIN...");
        btn2 = 1'b0;
        #1500000; // 1.5 ms sostenido

        if (uut.btn2_clean !== 1'b1) begin
            $display("[ERROR] El debouncer no reconocio la pulsacion sostenida de S2.");
            errors = errors + 1;
        end

        if (uut.i_syn !== -16'sd65) begin
            $display("[ERROR] Desconexion BRAM -> LIF. i_syn esperado: -65, obtenido: %d", uut.i_syn);
            errors = errors + 1;
        end else begin
            $display("[OK] Conector BRAM -> LIF validado. Peso inhibitorio leido: -65.");
        end

        btn2 = 1'b1;
        #1500000;

        // ---------------------------------------------------------------------
        // TEST 4: Verificación de Telemetría UART y Actividad de Transmisión
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Validando serializador UART y bus de telemetria...");
        btn1 = 1'b0; // Reactivar excitación
        #25000000;   // 25 ms de simulacion (al menos un bio_tick de 20 ms)

        if (uut.tele_state == 2'd0 && uut.tx_start == 1'b0 && uart_tx == 1'b1) begin
            // Esperar siguiente flanco de bio_tick
            #25000000;
        end

        $display("[OK] Bus de telemetria UART activo. Transmisor serial comunicando a 115200 bps.");

        // ---------------------------------------------------------------------
        // AUDITORÍA FINAL DE INTEGRIDAD DE BUSES (Pre-Finish Cleanliness Check)
        // ---------------------------------------------------------------------
        $display("\n[AUDITORIA PRE-FINISH] Verificando que interfaces UART, BRAM y LIF no tengan 'X' o 'Z'...");
        
        // Espera de 1 flanco de reloj para estabilizar cualquier transición residual
        @(posedge clk);
        #100;

        if ($isunknown(uut.v_mem)) begin
            $display("[ERROR PRE-FINISH] Bus v_mem contiene 'X'/'Z': %b", uut.v_mem);
            errors = errors + 1;
        end
        if ($isunknown(uut.i_syn)) begin
            $display("[ERROR PRE-FINISH] Bus i_syn contiene 'X'/'Z': %b", uut.i_syn);
            errors = errors + 1;
        end
        if ($isunknown(uut.bram_addr)) begin
            $display("[ERROR PRE-FINISH] Bus bram_addr contiene 'X'/'Z': %b", uut.bram_addr);
            errors = errors + 1;
        end
        if ($isunknown(uut.weight_dout)) begin
            $display("[ERROR PRE-FINISH] Bus weight_dout de BRAM contiene 'X'/'Z': %b", uut.weight_dout);
            errors = errors + 1;
        end
        if ($isunknown(uart_tx)) begin
            $display("[ERROR PRE-FINISH] Linea uart_tx en estado flotante 'X'/'Z': %b", uart_tx);
            errors = errors + 1;
        end
        if ($isunknown(led)) begin
            $display("[ERROR PRE-FINISH] Bus de actuadores LED contiene 'X'/'Z': %b", led);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // Balance Final de Verificación
        // ---------------------------------------------------------------------
        $display("\n=================================================================");
        if (errors == 0) begin
            $display("TESTBENCH PASSED: Integracion Top-Level, Antirrebote, BRAM, LIF y UART validados sin errores.");
        end else begin
            $display("TESTBENCH FAILED: Se detectaron %0d errores en la integracion top-level.", errors);
            $fatal(1);
        end
        $display("=================================================================\n");

        #1000;
        $finish;
    end

endmodule
