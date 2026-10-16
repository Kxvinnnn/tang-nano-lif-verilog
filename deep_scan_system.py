import os

def deep_scan():
    drives = [r"C:\\"]
    large_files = []
    
    print("Iniciando escaneo profundo de archivos grandes en C:\\ (>100 MB)...")
    for drive in drives:
        for root, dirs, files in os.walk(drive):
            # Omitir carpetas de sistema protegidas o innecesarias para agilizar y evitar bloqueos
            dirs[:] = [d for d in dirs if d.lower() not in ['$recycle.bin', 'system volume information', 'windows', 'program files', 'program files (x86)', 'programdata']]
            
            for f in files:
                fp = os.path.join(root, f)
                try:
                    size = os.path.getsize(fp)
                    if size > 100 * 1024 * 1024:  # Mayores a 100 MB
                        large_files.append((size, fp))
                except:
                    pass

    # Ordenar de mayor a menor
    large_files.sort(key=lambda x: x[0], reverse=True)
    
    print("\n=== ARCHIVOS MÁS GRANDES ENCONTRADOS (>100 MB) ===")
    for size, fp in large_files[:30]:
        print(f"{size / (1024**3):.2f} GB : {fp}")

deep_scan()
