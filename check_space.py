import ctypes

free_bytes = ctypes.c_ulonglong(0)
total_bytes = ctypes.c_ulonglong(0)
ctypes.windll.kernel32.GetDiskFreeSpaceExW("C:\\", None, ctypes.pointer(total_bytes), ctypes.pointer(free_bytes))
print(f"Espacio libre restante en C: {free_bytes.value / (1024**3):.2f} GB")
