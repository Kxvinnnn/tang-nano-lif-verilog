import serial
import time
import argparse
import sys
import serial.tools.list_ports

def parse_args():
    parser = argparse.ArgumentParser(description="Telemetría Neuromórfica SNN UART")
    parser.add_argument("--port", type=str, default=None, help="Puerto serie (ej. COM3 o /dev/ttyUSB0)")
    parser.add_argument("--baudrate", type=int, default=115200, help="Baudrate (por defecto: 115200)")
    return parser.parse_args()

def select_port_interactive():
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("[WARN] No se detectaron puertos serie conectados.")
        return None
    print("[INFO] Puertos serie disponibles:")
    for idx, p in enumerate(ports):
        print(f"  [{idx}] {p.device} - {p.description}")
    
    choice = input("Seleccione el índice del puerto a utilizar (o pulse Enter para simulador): ")
    if choice.strip() == "":
        return None
    try:
        idx = int(choice)
        return ports[idx].device
    except Exception:
        print("[ERROR] Selección inválida.")
        return None

def run_neuromorphic_demo():
    args = parse_args()
    port = args.port
    baudrate = args.baudrate

    if port is None:
        port = select_port_interactive()

    print(f"[INFO] Iniciando telemetría en puerto: {port} a {baudrate} baudios...")
    
    ser = None
    if port:
        try:
            ser = serial.Serial(port, baudrate, timeout=0.1)
            print(f"[INFO] Conexión establecida con éxito en {port}.")
        except Exception as e:
            print(f"[WARN] No se pudo abrir {port} ({e}). Activando modo simulador autónomo.")

    if ser is None:
        print("[SIMULADOR] Ejecutando simulación en vivo de neurona LIF...")
        for i in range(10):
            v_mem = min(1000, i * 120)
            spike = 1 if v_mem >= 1000 else 0
            print(f"[SIMULADOR] V_mem: {v_mem} mV | Spike: {spike} | LEDs: {bin(v_mem >> 7)}")
            time.sleep(0.4)
        print("[PASSED] Demostración completada en modo simulador.")
        return

    while True:
        try:
            byte = ser.read(1)
            if byte == b'\xaa':
                packet = ser.read(3)
                if len(packet) == 3:
                    v_mem = (packet[0] << 8) | packet[1]
                    flags = packet[2]
                    print(f"[UART DATA] V_mem: {v_mem} mV | Flags: {bin(flags)}")
        except KeyboardInterrupt:
            print("[INFO] Telemetría detenida por el usuario.")
            break
    ser.close()

if __name__ == '__main__':
    run_neuromorphic_demo()
