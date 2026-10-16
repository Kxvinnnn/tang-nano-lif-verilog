import os

snn_dir = r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode"
for root, dirs, files in os.walk(snn_dir):
    for f in files:
        fp = os.path.join(root, f)
        try:
            sz = os.path.getsize(fp)
            if sz > 50 * 1024 * 1024: # > 50MB
                print(f"{sz / (1024**2):.1f} MB: {fp}")
        except:
            pass
