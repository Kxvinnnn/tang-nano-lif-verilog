`timescale 1ns / 1ps

// =============================================================================
// Banco de Pruebas: tb_lif_neuron.v
// Módulo bajo prueba (DUT): lif_neuron.v
// Estándar de verificación: Verificación funcional y temporal a nivel RTL
// Reloj base del sistema: 27 MHz (Periodo: 37.037 ns)
// =============================================================================

module tb_lif_neuron;

    // -------------------------------------------------------------------------
    // Parámetros de Simulación y Constantes
    // -------------------------------------------------------------------------
    parameter CLK_PERIOD       = 37.037;  // 27.0 MHz (~37.037 ns)
    parameter CLK_HALF_PERIOD  = CLK_PERIOD / 2.0;

    parameter signed [15:0] V_TH         = 16'sd1000;
    parameter signed [15:0] V_MIN        = -16'sd250;
    parameter [4:0]         REFRAC_TICKS = 5'd16;

    // -------------------------------------------------------------------------
    // Señales de Estímulo y Monitoreo
    // -------------------------------------------------------------------------
    reg                clk;
    reg                rst_n;
    reg                bio_tick;
    reg  signed [15:0] synaptic_in;

    wire signed [15:0] v_mem;
    wire               spike;

    // Variables de control de verificación
    integer tick_counter;
    integer errors;
    integer spike_occurred_tick;
    reg     spike_detected;

    // -------------------------------------------------------------------------
    // Instanciación del Dispositivo Bajo Prueba (DUT)
    // -------------------------------------------------------------------------
    lif_neuron #(
        .V_TH         (V_TH),
        .V_MIN        (V_MIN),
        .REFRAC_TICKS (REFRAC_TICKS)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .bio_tick   (bio_tick),
        .current_in (synaptic_in),
        .spike_out  (spike),
        .v_mem      (v_mem)
    );

    // -------------------------------------------------------------------------
    // Generador de Reloj Maestro (27 MHz)
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_HALF_PERIOD) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Tarea: Generar un pulso síncrono de bio_tick (1 ciclo de reloj a 27 MHz)
    // -------------------------------------------------------------------------
    task send_bio_tick;
        input integer cycles_wait;
        begin
            @(posedge clk);
            #1;
            bio_tick = 1'b1;
            @(posedge clk);
            #1;
            bio_tick = 1'b0;
            tick_counter = tick_counter + 1;
            if (spike === 1'b1) begin
                spike_detected = 1'b1;
                spike_occurred_tick = tick_counter;
                $display("  >>> [EVENTO SPIKE DETECTADO] en Tick #%0d (Tiempo sim: %0t ps) superando V_TH=%0d", 
                         tick_counter, $time, V_TH);
            end
            // Intervalo inter-tick para simulación (permite visualizar la estabilidad entre ticks)
            repeat (cycles_wait) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia Principal de Estímulos y Verificación
    // -------------------------------------------------------------------------
    initial begin
        // Configuración de volcado VCD para análisis en GTKWave / Gowin Simulator
        $dumpfile("tb_lif_neuron.vcd");
        $dumpvars(0, tb_lif_neuron);

        // Inicialización de variables
        rst_n               = 1'b0;
        bio_tick            = 1'b0;
        synaptic_in         = 16'sd0;
        tick_counter        = 0;
        errors              = 0;
        spike_detected      = 1'b0;
        spike_occurred_tick = 0;

        $display("============================================================================");
        $display("  INICIANDO VERIFICACIÓN FUNCIONAL RTL: NEURONA LEAKY INTEGRATE-AND-FIRE");
        $display("  DUT: lif_neuron.v | Reloj: 27 MHz | V_TH=%0d | V_MIN=%0d | Refrac=%0d ticks", 
                 V_TH, V_MIN, REFRAC_TICKS);
        $display("============================================================================");

        // ---------------------------------------------------------------------
        // FASE 0: Reset Asíncrono y Verificación de Reposo Inicial
        // ---------------------------------------------------------------------
        $display("[FASE 0] Verificando Reset y Estado Inicial...");
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        if (v_mem !== 16'sd0 || spike !== 1'b0) begin
            $display("  [ERROR] Estado post-reset incorrecto: v_mem=%0d (esp: 0), spike=%b (esp: 0)", v_mem, spike);
            errors = errors + 1;
        end else begin
            $display("  [OK] Reset exitoso: v_mem = %0d, spike = %b", v_mem, spike);
        end

        // ---------------------------------------------------------------------
        // FASE 1: Inyección Continua de Corriente Excitatoria (+68)
        // ---------------------------------------------------------------------
        $display("\n[FASE 1] Inyectando Corriente Excitatoria Sostenida (+68)...");
        synaptic_in = 16'sd68;

        while (!spike_detected && tick_counter < 100) begin
            send_bio_tick(10); // Pulso bio_tick seguido de 10 ciclos clk
            if (!spike_detected && (tick_counter % 5 == 0)) begin
                $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                         tick_counter, synaptic_in, v_mem, spike);
            end
        end

        if (!spike_detected) begin
            $display("  [ERROR] La neurona no disparó spike tras 100 ticks con synaptic_in=+68.");
            errors = errors + 1;
        end else begin
            $display("  [OK] Disparo exitoso en Tick #%0d. Verificando periodo refractario...", spike_occurred_tick);
        end

        // ---------------------------------------------------------------------
        // FASE 2: Verificación del Periodo Refractario (16 ticks forzados a 0)
        // ---------------------------------------------------------------------
        $display("\n[FASE 2] Verificando Periodo Refractario (16 ticks bloqueados en v_mem = 0)...");
        // Mantenemos la excitación activa (+68); la neurona DEBE ignorarla durante refractario
        begin : check_refractory
            integer r_i;
            for (r_i = 1; r_i <= REFRAC_TICKS; r_i = r_i + 1) begin
                send_bio_tick(10);
                if (v_mem !== 16'sd0) begin
                    $display("  [ERROR] Falla en refractario tick #%0d (+%0d del spike): v_mem=%0d (debe ser 0)", 
                             tick_counter, r_i, v_mem);
                    errors = errors + 1;
                end
                if (spike !== 1'b0) begin
                    $display("  [ERROR] Spike espurio durante refractario en tick #%0d", tick_counter);
                    errors = errors + 1;
                end
            end
            $display("  [OK] Periodo refractario completado estrictamente en v_mem = 0.");
        end

        // ---------------------------------------------------------------------
        // FASE 3: Transición a Reposo y Prueba de Integración Post-Refractario
        // ---------------------------------------------------------------------
        $display("\n[FASE 3] Reanudando Integración tras Periodo Refractario (3 ticks)...");
        repeat (3) begin
            send_bio_tick(10);
            $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                     tick_counter, synaptic_in, v_mem, spike);
        end

        if (v_mem <= 16'sd0) begin
            $display("  [ERROR] La neurona no reanudó la integración tras el refractario.");
            errors = errors + 1;
        end else begin
            $display("  [OK] Integración reanudada exitosamente: v_mem = %0d.", v_mem);
        end

        // ---------------------------------------------------------------------
        // FASE 4: Inyección de Corriente Inhibitoria (-65) e Hiperpolarización
        // ---------------------------------------------------------------------
        $display("\n[FASE 4] Inyectando Corriente Inhibitoria (-65) hacia Hiperpolarización (-250)...");
        synaptic_in = -16'sd65;

        // Inyectamos 20 ticks inhibitorios para asegurar llegada al piso V_MIN (-250)
        repeat (20) begin
            send_bio_tick(10);
            if (tick_counter % 4 == 0) begin
                $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                         tick_counter, synaptic_in, v_mem, spike);
            end
        end

        // Comprobar saturación en V_MIN (-250)
        if (v_mem !== V_MIN) begin
            $display("  [ERROR] Hiperpolarización no saturó en V_MIN (%0d): v_mem = %0d", V_MIN, v_mem);
            errors = errors + 1;
        end else begin
            $display("  [OK] Hiperpolarización verificada: v_mem saturó exactamente en %0d.", v_mem);
        end

        // ---------------------------------------------------------------------
        // FASE 5: Fuga Natural Simétrica desde Hiperpolarización hacia Reposo (0)
        // ---------------------------------------------------------------------
        $display("\n[FASE 5] Retirando Estímulo (synaptic_in = 0). Verificando fuga natural hacia 0...");
        synaptic_in = 16'sd0;

        repeat (55) begin
            send_bio_tick(10);
            if (tick_counter % 10 == 0) begin
                $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                         tick_counter, synaptic_in, v_mem, spike);
            end
        end

        if (v_mem !== 16'sd0) begin
            $display("  [ERROR] Fuga simétrica no estabilizó en 0: v_mem = %0d", v_mem);
            errors = errors + 1;
        end else begin
            $display("  [OK] Potencial estabilizado completamente en reposo (v_mem = 0).");
        end

        // ---------------------------------------------------------------------
        // Resumen Final de la Simulación
        // ---------------------------------------------------------------------
        $display("\n============================================================================");
        if (errors == 0) begin
            $display("  >>> TESTBENCH PASSED: TODAS LAS PRUEBAS FUNCIONALES FUERON VALIDADAS <<<");
            $display("  Archivo de ondas generado: tb_lif_neuron.vcd");
            $display("  Total de ticks evaluados: %0d", tick_counter);
        end else begin
            $display("  >>> TESTBENCH FAILED: Se detectaron %0d errores en la simulación <<<", errors);
        end
        $display("============================================================================\n");

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule
