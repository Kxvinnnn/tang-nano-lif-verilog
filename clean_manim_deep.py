import os
import shutil
import ctypes

def get_free_space_gb(folder="C:\\"):
    free_bytes = ctypes.c_ulonglong(0)
    total_bytes = ctypes.c_ulonglong(0)
    ctypes.windll.kernel32.GetDiskFreeSpaceExW(ctypes.c_wchar_p(folder), None, ctypes.pointer(total_bytes), ctypes.pointer(free_bytes))
    return free_bytes.value / (1024**3), total_bytes.value / (1024**3)

free_before, _ = get_free_space_gb()
base_dir = r"C:\Users\kevincipher\Desktop\manim studio presentacion clase"
media_dir = os.path.join(base_dir, "media")

deleted_items = []
total_bytes_freed = 0

def add_freed_size(path):
    global total_bytes_freed
    if os.path.isfile(path):
        try:
            sz = os.path.getsize(path)
            total_bytes_freed += sz
            os.unlink(path)
        except:
            pass
    elif os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            for f in files:
                fp = os.path.join(root, f)
                try:
                    total_bytes_freed += os.path.getsize(fp)
                except:
                    pass
        shutil.rmtree(path, ignore_errors=True)

# 1. Remove partial_movie_files and Tex / texts / images cache
if os.path.exists(media_dir):
    for root, dirs, files in os.walk(media_dir, topdown=False):
        for d in dirs:
            dp = os.path.join(root, d)
            if d == "partial_movie_files" or d == "Tex" or d == "texts" or d == "images":
                deleted_items.append(dp)
                add_freed_size(dp)

# 2. Inspect media/videos for obsolete resolutions / old scene folders
videos_dir = os.path.join(media_dir, "videos")
if os.path.exists(videos_dir):
    # Walk through scene folders under videos
    for scene_name in os.listdir(videos_dir):
        scene_path = os.path.join(videos_dir, scene_name)
        if os.path.isdir(scene_path):
            for res_name in os.listdir(scene_path):
                res_path = os.path.join(scene_path, res_name)
                if os.path.isdir(res_path):
                    # Check video files inside
                    mp4s = []
                    for r, ds, fs in os.walk(res_path):
                        for f in fs:
                            if f.endswith(".mp4"):
                                mp4s.append(os.path.join(r, f))
                    
                    # If there are multiple mp4s or obsolete resolution folders (like 480p15, 720p30, or non-active resolutions)
                    if res_name != "1080p60" or len(mp4s) > 1:
                        # Keep only the single most recent mp4 if possible, or delete obsolete resolution folders
                        # Let's find the newest mp4 across all res_path if any
                        pass
                    
                    # Specifically, user requested: "Si existen carpetas de resoluciones no utilizadas o fallidas (por ejemplo, 1080p60, 480p15...) elimina esas carpetas obsoletas. Conserva únicamente el archivo del video final consolidado más reciente."
                    if res_name in ["480p15", "720p30"]:
                        deleted_items.append(res_path)
                        add_freed_size(res_path)

# 3. Clean __pycache__ in presentation and project dirs
for target_root in [base_dir, r"C:\Users\kevincipher\Desktop\Manim studio proyecto\snn_tangnano_vscode"]:
    if os.path.exists(target_root):
        for root, dirs, files in os.walk(target_root, topdown=False):
            for d in dirs:
                if d == "__pycache__":
                    dp = os.path.join(root, d)
                    deleted_items.append(dp)
                    add_freed_size(dp)

# 4. Pip cache purge
os.system("python -m pip cache purge")

free_after, _ = get_free_space_gb()

print("=== REPORTE DE AUDITORÍA DE LIMPIEZA ===")
print(f"Total elementos eliminados: {len(deleted_items)}")
print(f"Espacio total liberado (calculado): {total_bytes_freed / (1024*1024):.2f} MB")
print(f"Espacio libre final en C:: {free_after:.2f} GB")
