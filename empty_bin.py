import os
import ctypes

def get_free_space_gb(folder="C:\\"):
    free_bytes = ctypes.c_ulonglong(0)
    total_bytes = ctypes.c_ulonglong(0)
    ctypes.windll.kernel32.GetDiskFreeSpaceExW(ctypes.c_wchar_p(folder), None, ctypes.pointer(total_bytes), ctypes.pointer(free_bytes))
    return free_bytes.value / (1024**3), total_bytes.value / (1024**3)

free_before, _ = get_free_space_gb()
ctypes.windll.shell32.SHEmptyRecycleBinW(None, None, 7)
free_after, _ = get_free_space_gb()

print(f"Freed from Recycle Bin: {free_after - free_before:.2f} GB")
print(f"New free space: {free_after:.2f} GB")
