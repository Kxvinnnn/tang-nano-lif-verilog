import subprocess

yosys_path = r"C:\oss-cad-suite\bin\yosys.exe"
script = """
read_verilog src_verilog/hdl/bram_synapse.v
read_verilog src_verilog/hdl/lif_neuron.v
read_verilog src_verilog/hdl/top_snn_system.v
read_verilog src_verilog/hdl/uart_transceiver.v
synth_gowin -top top_snn_system -json build/synth.json
"""

with open("synth_script.ys", "w") as f:
    f.write(script)

# Run via python using a shell or direct invocation if possible, or build an alternative workflow
print("Script de síntesis escrito.")
