import subprocess

res = subprocess.run(["iverilog", "-g2012", "-s", "tb_top_lif_demo", "-o", "build/sim_demo.vvp", "src_verilog/top_lif_demo.v", "src_verilog/tb_top_lif_demo.v"], capture_output=True, text=True)
print("Iverilog compile:", res.returncode, res.stderr)

if res.returncode == 0:
    res2 = subprocess.run(["vvp", "build/sim_demo.vvp"], capture_output=True, text=True)
    print("VVP run:", res2.returncode, res2.stdout, res2.stderr)
