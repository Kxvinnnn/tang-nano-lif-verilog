import os

desktop = r"C:\Users\kevincipher\Desktop"
for entry in os.listdir(desktop):
    full_path = os.path.join(desktop, entry)
    if os.path.isdir(full_path):
        size = 0
        for root, dirs, files in os.walk(full_path):
            for f in files:
                try:
                    size += os.path.getsize(os.path.join(root, f))
                except:
                    pass
        print(f"{entry}: {size / (1024**3):.2f} GB")
    elif os.path.isfile(full_path):
        try:
            size = os.path.getsize(full_path)
            print(f"{entry} (file): {size / (1024**3):.2f} GB")
        except:
            pass
