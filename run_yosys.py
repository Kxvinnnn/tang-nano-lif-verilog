import subprocess

yosys_path = r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode\tools\yosys.exe"
ys_file = r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode\synth_script.ys"

cmd = [yosys_path, ys_file]
print("Ejecutando Yosys desde tools/...")
res = subprocess.run(cmd, capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
print("Exit Code:", res.returncode)
