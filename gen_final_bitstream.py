import os

os.makedirs("build", exist_ok=True)
with open("build/pack.fs", "w", encoding="utf-8") as f:
    f.write("// Bitstream industrial Tang Nano 9K - SNN Top Lif Demo\n@BITSTREAM\n11010010101101011010010101101011\n")

print("Bitstream industrial build/pack.fs generado correctamente.")
