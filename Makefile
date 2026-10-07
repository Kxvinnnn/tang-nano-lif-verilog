.PHONY: data sim synth-open prog-sram prog-flash clean

data:
	python3 src_py/train_and_export.py

sim:
	iverilog -g2012 -s tb_top_lif_demo -o build/sim_demo.vvp src_verilog/bram_synapse_matrix.v src_verilog/hdl/lif_neuron.v src_verilog/hdl/uart_transceiver.v src_verilog/debounce_sync.v src_verilog/top_lif_demo.v src_verilog/tb_top_lif_demo.v
	vvp build/sim_demo.vvp

synth-open:
	echo "Iniciando síntesis abierta..."
	yosys -p "read_verilog src_verilog/bram_synapse_matrix.v src_verilog/hdl/lif_neuron.v src_verilog/hdl/uart_transceiver.v src_verilog/debounce_sync.v src_verilog/top_lif_demo.v; synth_gowin -top top_lif_demo -json build/synth.json"
	nextpnr-gowin --json build/synth.json --write build/pnr.json --device GW1NR-LV9QN88PC6/I5 --cst constraints/tangnano9k.cst
	gowin_pack -d GW1N-9C -o build/pack.fs build/pnr.json

prog-sram:
	openFPGALoader -b tangnano9k build/pack.fs

prog-flash:
	openFPGALoader -b tangnano9k -f build/pack.fs

clean:
	rm -rf build/*
