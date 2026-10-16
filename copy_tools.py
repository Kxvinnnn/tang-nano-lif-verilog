import os
import shutil

oss_bin = r"C:\oss-cad-suite\bin"
local_bin = r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode\tools"
os.makedirs(local_bin, exist_ok=True)

for f in ["yosys.exe", "yosys-abc.exe", "nextpnr-himbaechel.exe", "gowin_pack.exe"]:
    src = os.path.join(oss_bin, f)
    dst = os.path.join(local_bin, f)
    if os.path.exists(src):
        shutil.copy2(src, dst)
        print(f"Copiado {f}")

print("Copia completada.")
