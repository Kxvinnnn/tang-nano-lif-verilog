import os
import shutil
import subprocess
import sys
from pathlib import Path


sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent
SUITE_ROOT = Path(os.environ.get("OSS_CAD_SUITE", r"C:\oss-cad-suite"))
SUITE_BIN = SUITE_ROOT / "bin"
TOOL_SEARCH_PATH = os.pathsep.join(
    part
    for part in (
        os.environ.get("PATH", ""),
        str(SUITE_BIN),
        str(ROOT / "tools"),
    )
    if part
)


def find_tool(name):
    return shutil.which(name, path=TOOL_SEARCH_PATH)


def run_tool(executable, args, label):
    tool_environment = os.environ.copy()
    tool_environment["PATH"] = os.pathsep.join(
        part
        for part in (
            str(SUITE_BIN),
            str(SUITE_ROOT / "lib"),
            tool_environment.get("PATH", ""),
        )
        if part
    )

    result = subprocess.run(
        [executable, *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=tool_environment,
        check=False,
    )
    print(f"{label} STDOUT:")
    print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    print(f"{label} STDERR:")
    print(result.stderr, end="" if result.stderr.endswith("\n") else "\n")
    print(f"{label} Exit Code: {result.returncode}")
    return result


def main():
    yosys = find_tool("yosys.exe")
    if not yosys:
        print("ERROR: no se encontró Yosys. No se generará ningún artefacto.")
        return 1

    rtl_files = (
        "src_verilog/bram_synapse_matrix.v",
        "src_verilog/hdl/lif_neuron.v",
        "src_verilog/hdl/uart_transceiver.v",
        "src_verilog/debounce_sync.v",
        "src_verilog/top_lif_demo.v",
    )
    yosys_script = (
        f"read_verilog {' '.join(rtl_files)}; "
        "hierarchy -check -top top_lif_demo; "
        "synth_gowin -noabc9 -top top_lif_demo -json top_lif_demo.json"
    )

    print("Ejecutando síntesis RTL real con Yosys...")
    result = run_tool(yosys, ["-p", yosys_script], "Yosys")
    if result.returncode:
        return result.returncode
    if not (ROOT / "top_lif_demo.json").is_file():
        print("ERROR: Yosys terminó sin generar top_lif_demo.json.")
        return 1

    nextpnr = find_tool("nextpnr-himbaechel.exe")
    if not nextpnr:
        print("Síntesis lógica completada. Listo para PnR en Gowin EDA.")
        return 0

    pnr_args = [
        "--device",
        "GW1NR-LV9QN88PC6/I5",
        "--vopt",
        "family=GW1N-9C",
        "--vopt",
        "cst=constraints/tangnano9k.cst",
        "--json",
        "top_lif_demo.json",
        "--write",
        "top_lif_demo_pnr.json",
    ]
    print("Ejecutando Place & Route real con nextpnr-himbaechel...")
    result = run_tool(nextpnr, pnr_args, "nextpnr-himbaechel")
    if result.returncode:
        return result.returncode
    if not (ROOT / "top_lif_demo_pnr.json").is_file():
        print("ERROR: nextpnr-himbaechel terminó sin generar top_lif_demo_pnr.json.")
        return 1

    gowin_pack = find_tool("gowin_pack.exe")
    if not gowin_pack:
        print("ERROR: no se encontró gowin_pack; no se generará ningún bitstream.")
        return 1

    print("Empaquetando el bitstream con gowin_pack real...")
    result = run_tool(
        gowin_pack,
        ["-d", "GW1N-9C", "-o", "top_lif_demo.fs", "top_lif_demo_pnr.json"],
        "gowin_pack",
    )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
