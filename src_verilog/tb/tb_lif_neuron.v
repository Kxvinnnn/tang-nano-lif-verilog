`timescale 1ns / 1ps
// =============================================================================
// Testbench: tb_lif_neuron.v
// Device Under Test (DUT): lif_neuron.v
// Verification Standard: Cycle-Accurate Functional & Temporal RTL Verification
// Master Clock Frequency: 27.0 MHz (Period: 37.037 ns)
// =============================================================================

module tb_lif_neuron;

    // -------------------------------------------------------------------------
    // Simulation Parameters & Time Constants
    // -------------------------------------------------------------------------
    parameter CLK_PERIOD       = 37.037;  // 27.0 MHz (~37.037 ns)
    parameter CLK_HALF_PERIOD  = CLK_PERIOD / 2.0;

    parameter signed [15:0] V_TH         = 16'sd1000;
    parameter signed [15:0] V_MIN        = -16'sd250;
    parameter [4:0]         REFRAC_TICKS = 5'd16;

    // -------------------------------------------------------------------------
    // Stimulus and Monitor Signals
    // -------------------------------------------------------------------------
    reg                clk;
    reg                rst_n;
    reg                bio_tick;
    reg  signed [15:0] synaptic_in;

    wire signed [15:0] v_mem;
    wire               spike;

    // Verification control variables
    integer tick_counter;
    integer errors;
    integer spike_occurred_tick;
    reg     spike_detected;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
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
    // Master Clock Generator (27.0 MHz)
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_HALF_PERIOD) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Task: Generate Synchronous bio_tick Pulse (1 clock cycle @ 27 MHz)
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
                $display("  >>> [SPIKE EVENT DETECTED] at Tick #%0d (Sim Time: %0t ps) crossing V_TH=%0d", 
                         tick_counter, $time, V_TH);
            end
            // Inter-tick spacing for simulation waveforms
            repeat (cycles_wait) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Stimulus and Assertion Sequence
    // -------------------------------------------------------------------------
    initial begin
        // VCD waveform dump for GTKWave / ModelSim / Gowin Simulator
        $dumpfile("tb_lif_neuron.vcd");
        $dumpvars(0, tb_lif_neuron);

        // Variable initialization
        rst_n               = 1'b0;
        bio_tick            = 1'b0;
        synaptic_in         = 16'sd0;
        tick_counter        = 0;
        errors              = 0;
        spike_detected      = 1'b0;
        spike_occurred_tick = 0;

        $display("============================================================================");
        $display("  STARTING RTL FUNCTIONAL VERIFICATION: LEAKY INTEGRATE-AND-FIRE NEURON");
        $display("  DUT: lif_neuron.v | Clock: 27 MHz | V_TH=%0d | V_MIN=%0d | Refrac=%0d ticks", 
                 V_TH, V_MIN, REFRAC_TICKS);
        $display("============================================================================");

        // ---------------------------------------------------------------------
        // PHASE 0: Asynchronous Reset and Initial Rest State
        // ---------------------------------------------------------------------
        $display("[PHASE 0] Verifying Reset and Initial Rest State...");
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        if (v_mem !== 16'sd0 || spike !== 1'b0) begin
            $display("  [TB-ERROR] Incorrect post-reset state: v_mem=%0d (exp: 0), spike=%b (exp: 0)", v_mem, spike);
            errors = errors + 1;
        end else begin
            $display("  [OK] Reset verified: v_mem = %0d, spike = %b", v_mem, spike);
        end

        // ---------------------------------------------------------------------
        // PHASE 1: Sustained Excitatory Current Injection (+68)
        // ---------------------------------------------------------------------
        $display("\n[PHASE 1] Injecting Sustained Excitatory Current (+68)...");
        synaptic_in = 16'sd68;

        while (!spike_detected && tick_counter < 100) begin
            send_bio_tick(10);
            if (!spike_detected && (tick_counter % 5 == 0)) begin
                $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                         tick_counter, synaptic_in, v_mem, spike);
            end
        end

        if (!spike_detected) begin
            $display("  [TB-ERROR] Neuron failed to fire spike after 100 ticks with synaptic_in=+68.");
            errors = errors + 1;
        end else begin
            $display("  [OK] Action potential fired at Tick #%0d. Verifying refractory lockout...", spike_occurred_tick);
        end

        // ---------------------------------------------------------------------
        // PHASE 2: Absolute Refractory Period Verification (16 ticks clamped at 0)
        // ---------------------------------------------------------------------
        $display("\n[PHASE 2] Verifying Absolute Refractory Period (16 ticks locked at v_mem = 0)...");
        // Keep excitation active (+68); the neuron MUST strictly ignore it during refractory lockout
        begin : check_refractory
            integer r_i;
            for (r_i = 1; r_i <= REFRAC_TICKS; r_i = r_i + 1) begin
                send_bio_tick(10);
                if (v_mem !== 16'sd0) begin
                    $display("  [TB-ERROR] Refractory violation at tick #%0d (+%0d from spike): v_mem=%0d (must be 0)", 
                             tick_counter, r_i, v_mem);
                    errors = errors + 1;
                end
                if (spike !== 1'b0) begin
                    $display("  [TB-ERROR] Spurious spike during refractory lockout at tick #%0d", tick_counter);
                    errors = errors + 1;
                end
            end
            $display("  [OK] Refractory period completed strictly clamped at v_mem = 0.");
        end

        // ---------------------------------------------------------------------
        // PHASE 3: Integration Resumption Post-Refractory Lockout
        // ---------------------------------------------------------------------
        $display("\n[PHASE 3] Resuming Integration Post-Refractory Lockout (3 ticks)...");
        repeat (3) begin
            send_bio_tick(10);
            $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                     tick_counter, synaptic_in, v_mem, spike);
        end

        if (v_mem <= 16'sd0) begin
            $display("  [TB-ERROR] Neuron failed to resume integration after refractory period.");
            errors = errors + 1;
        end else begin
            $display("  [OK] Integration resumed successfully: v_mem = %0d.", v_mem);
        end

        // ---------------------------------------------------------------------
        // PHASE 4: Inhibitory Current Injection (-65) and Hyperpolarization
        // ---------------------------------------------------------------------
        $display("\n[PHASE 4] Injecting Inhibitory Current (-65) towards Hyperpolarization Floor (-250)...");
        synaptic_in = -16'sd65;

        repeat (20) begin
            send_bio_tick(10);
            if (tick_counter % 4 == 0) begin
                $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                         tick_counter, synaptic_in, v_mem, spike);
            end
        end

        // Check saturation at V_MIN (-250)
        if (v_mem !== V_MIN) begin
            $display("  [TB-ERROR] Hyperpolarization failed to clamp at V_MIN (%0d): v_mem = %0d", V_MIN, v_mem);
            errors = errors + 1;
        end else begin
            $display("  [OK] Hyperpolarization verified: v_mem clamped exactly at %0d.", v_mem);
        end

        // ---------------------------------------------------------------------
        // PHASE 5: Symmetric Natural Leak from Hyperpolarization to Rest (0)
        // ---------------------------------------------------------------------
        $display("\n[PHASE 5] Removing Stimulus (synaptic_in = 0). Verifying natural leak towards 0...");
        synaptic_in = 16'sd0;

        repeat (55) begin
            send_bio_tick(10);
            if (tick_counter % 10 == 0) begin
                $display("      Tick #%02d | synaptic_in = %+4d | v_mem = %4d | spike = %b", 
                         tick_counter, synaptic_in, v_mem, spike);
            end
        end

        if (v_mem !== 16'sd0) begin
            $display("  [TB-ERROR] Symmetric leak failed to stabilize at 0: v_mem = %0d", v_mem);
            errors = errors + 1;
        end else begin
            $display("  [OK] Membrane potential fully stabilized at resting baseline (v_mem = 0).");
        end

        // ---------------------------------------------------------------------
        // Final Simulation Summary
        // ---------------------------------------------------------------------
        $display("\n============================================================================");
        if (errors == 0) begin
            $display("  >>> TESTBENCH PASSED: All functional verification tests validated with 0 errors. <<<");
            $display("  Waveform file generated: tb_lif_neuron.vcd");
            $display("  Total biological ticks evaluated: %0d", tick_counter);
        end else begin
            $display("  >>> TESTBENCH FAILED: Detected %0d errors in simulation <<<", errors);
            $fatal(1);
        end
        $display("============================================================================\n");

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule
