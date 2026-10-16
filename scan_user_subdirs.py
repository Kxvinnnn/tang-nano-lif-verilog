import os

user_profile = r"C:\Users\kevincipher"
for entry in os.listdir(user_profile):
    if entry.startswith('.'):
        continue
    full_path = os.path.join(user_profile, entry)
    if os.path.isdir(full_path):
        size = 0
        for root, dirs, files in os.walk(full_path):
            for f in files:
                try:
                    size += os.path.getsize(os.path.join(root, f))
                except:
                    pass
        print(f"{entry}: {size / (1024**3):.2f} GB")
