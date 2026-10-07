import subprocess

yosys_path = r"C:\oss-cad-suite\bin\yosys.exe"
ys_path = r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode\synth_script.ys"

try:
    res = subprocess.run([yosys_path, ys_path], capture_output=True, text=True, timeout=60)
    print("STDOUT:", res.stdout[:500])
    print("STDERR:", res.stderr[:500])
    print("Returncode:", res.returncode)
except Exception as e:
    print("Error:", e)
