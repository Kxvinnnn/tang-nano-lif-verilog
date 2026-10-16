.PHONY: data sim sim-system synth-open prog-sram prog-flash clean

data:
	python3 src_py/train_and_export.py

sim:
	iverilog -g2012 -s tb_lif_neuron -o build/sim_tb_lif_neuron.vvp src_verilog/hdl/lif_neuron.v src_verilog/tb/tb_lif_neuron.v
	vvp build/sim_tb_lif_neuron.vvp

sim-system:
	iverilog -g2012 -s tb_top_system -o build/sim_tb_top_system.vvp src_verilog/hdl/button_debouncer.v src_verilog/bram_synapse_matrix.v src_verilog/hdl/lif_neuron.v src_verilog/hdl/uart_transceiver.v src_verilog/top_lif_demo.v src_verilog/tb/tb_top_system.v
	vvp build/sim_tb_top_system.vvp

synth-open:
	echo "Iniciando síntesis abierta..."
	python run_yosys.py

prog-sram:
	openFPGALoader -b tangnano9k top_lif_demo.fs

prog-flash:
	openFPGALoader -b tangnano9k -f top_lif_demo.fs

clean:
	rm -rf build/*
