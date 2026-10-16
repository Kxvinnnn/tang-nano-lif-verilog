import os

snn_dir = r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode"
for entry in os.listdir(snn_dir):
    full_path = os.path.join(snn_dir, entry)
    if os.path.isdir(full_path):
        size = 0
        for root, dirs, files in os.walk(full_path):
            for f in files:
                try:
                    size += os.path.getsize(os.path.join(root, f))
                except:
                    pass
        print(f"{entry}: {size / (1024**3):.2f} GB")
