import shutil
import os

root_dest = "C:/Users/kevincipher/Desktop/Manim studio proyecto"
root_src = "C:/Users/kevincipher/Desktop/Manim studio proyecto/snn_tangnano_vscode"

print("Sincronizando contenidos hacia el nivel superior...")

for item in os.listdir(root_src):
    s = os.path.join(root_src, item)
    d = os.path.join(root_dest, item)
    if item == ".git":
        continue
    if os.path.isdir(s):
        if os.path.exists(d):
            shutil.rmtree(d)
        shutil.copytree(s, d)
        print("Carpeta copiada:", item)
    else:
        shutil.copy2(s, d)
        print("Archivo copiado:", item)

print("Sincronización completada.")
