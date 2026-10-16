import os

def scan_drive(path, max_depth=2, current_depth=0):
    if current_depth > max_depth:
        return 0
    total_size = 0
    try:
        entries = os.listdir(path)
    except PermissionError:
        return 0
    except FileNotFoundError:
        return 0

    for entry in entries:
        if entry.startswith('$') or entry.lower() in ['system volume information', 'recycle.bin']:
            continue
        full_path = os.path.join(path, entry)
        if os.path.islink(full_path):
            continue
        if os.path.isfile(full_path):
            try:
                total_size += os.path.getsize(full_path)
            except:
                pass
        elif os.path.isdir(full_path):
            sub_size = scan_drive(full_path, max_depth, current_depth + 1)
            total_size += sub_size
            if current_depth == 0 and sub_size > 500 * 1024 * 1024:  # > 500MB at root/user level
                print(f"[DIR] {full_path}: {sub_size / (1024**3):.2f} GB")
    return total_size

print("--- Scanning C:\\ root top folders ---")
scan_drive(r"C:\\", max_depth=1)

print("\n--- Scanning User Profile (C:\\Users\\kevincipher) ---")
scan_drive(r"C:\Users\kevincipher", max_depth=1)
