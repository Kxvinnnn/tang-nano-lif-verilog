import os

os.makedirs("data", exist_ok=True)
os.makedirs("src_verilog", exist_ok=True)
os.makedirs("src_py", exist_ok=True)
os.makedirs("constraints", exist_ok=True)
os.makedirs("build", exist_ok=True)

weights = [
    "0200", # Peso sináptico débil
    "0800", # Peso sináptico fuerte
    "0100",
    "0400",
    "0150",
    "0500",
    "0250",
    "0600"
]

with open("data/pesos_sinapticos.hex", "w", encoding="utf-8") as f:
    for w in weights:
        f.write(w + "\n")

print("data/pesos_sinapticos.hex generado con éxito.")
