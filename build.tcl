add_file -type verilog "src_verilog/top_lif_demo.v"
add_file -type verilog "src_verilog/hdl/lif_neuron.v"
add_file -type verilog "src_verilog/hdl/uart_transceiver.v"
add_file -type verilog "src_verilog/bram_synapse_matrix.v"
add_file -type verilog "src_verilog/debounce_sync.v"
add_file -type verilog "src_verilog/hdl/button_debouncer.v"
add_file -type cst "constraints/tangnano9k.cst"
add_file -type sdc "constraints/tangnano9k.sdc"
set_device -name GW1NR-9C GW1NR-LV9QN88PC6/I5
set_option -top_module top_lif_demo
set_option -output_base_name LIF_Hardware
run all
