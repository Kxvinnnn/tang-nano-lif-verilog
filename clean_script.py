import os
import ctypes
import shutil

def get_free_space_gb(folder="C:\\"):
    free_bytes = ctypes.c_ulonglong(0)
    total_bytes = ctypes.c_ulonglong(0)
    ctypes.windll.kernel32.GetDiskFreeSpaceExW(ctypes.c_wchar_p(folder), None, ctypes.pointer(total_bytes), ctypes.pointer(free_bytes))
    return free_bytes.value / (1024**3), total_bytes.value / (1024**3)

free_before, total = get_free_space_gb()

os.system("python -m pip cache purge")

temp_dir = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Temp")
deleted_size = 0
if os.path.exists(temp_dir):
    for item in os.listdir(temp_dir):
        item_path = os.path.join(temp_dir, item)
        try:
            if os.path.isfile(item_path) or os.path.islink(item_path):
                size = os.path.getsize(item_path)
                os.unlink(item_path)
                deleted_size += size
            elif os.path.isdir(item_path):
                dsize = 0
                for root, dirs, files in os.walk(item_path):
                    for f in files:
                        fp = os.path.join(root, f)
                        try:
                            dsize += os.path.getsize(fp)
                        except:
                            pass
                shutil.rmtree(item_path, ignore_errors=True)
                deleted_size += dsize
        except Exception as e:
            pass

free_after, _ = get_free_space_gb()
freed_gb = free_after - free_before

print(f"Freed GB: {freed_gb:.2f}")
print(f"Free space remaining C: {free_after:.2f} GB")
