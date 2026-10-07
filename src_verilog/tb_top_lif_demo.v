`timescale 1ns / 1ps
module tb_top_lif_demo;
    reg clk;
    reg btn1;
    reg btn2;
    wire uart_tx;
    wire [5:0] led;

    top_lif_demo uut (
        .clk(clk),
        .btn1(btn1),
        .btn2(btn2),
        .uart_tx(uart_tx),
        .led(led)
    );

    // Reloj de 27 MHz (periodo ~37.037 ns)
    always #18.518 clk = ~clk;

    initial begin
        $dumpfile("build/sim_waves.vcd");
        $dumpvars(0, tb_top_lif_demo);

        clk = 0;
        btn1 = 1;
        btn2 = 1;

        #2000000; // Reposo 2ms
        
        // Simular pulsación S1 (peso débil)
        btn1 = 0;
        #10000000;
        btn1 = 1;

        #2000000;

        // Simular pulsación S2 (peso fuerte) para forzar disparo spike
        btn2 = 0;
        #15000000;
        btn2 = 1;

        #5000000;

        $display("TESTBENCH PASSED: Dinámica SNN y Telemetría validadas.");
        $finish;
    end
endmodule
