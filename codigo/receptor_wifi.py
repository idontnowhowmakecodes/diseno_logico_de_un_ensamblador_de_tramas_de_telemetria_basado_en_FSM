import socket
import os
import csv
from datetime import datetime
from Crypto.Cipher import AES

# CONFIGURACIÓN

UDP_IP = "0.0.0.0"       # Escuchar en todas las interfaces de red
UDP_PORT = 5005          # Mismo puerto que configuraremos en el ESP32

# Clave de 32 bytes (AES-256) y Vector de Inicialización de 16 bytes (CBC)

AES_KEY = b"idntmkecodes_32bytes_long_key_12" 
AES_IV  = b"idntmkecodes_iv_"

MAX_ROWS_PER_FILE = 50000 # Cantidad máxima de envíos por tabla
OUTPUT_FOLDER = "datos_historicos"

# INICIALIZACIÓN
if not os.path.exists(OUTPUT_FOLDER):
    os.makedirs(OUTPUT_FOLDER)

# Desencriptar AES-256-CBC
def decrypt_payload(encrypted_data):
    cipher = AES.new(AES_KEY, AES.MODE_CBC, AES_IV)
    decrypted = cipher.decrypt(encrypted_data)
    # Eliminar el relleno nulo (\x00) usado por el ESP32 para alinear bloques
    return decrypted.rstrip(b'\x00').decode('utf-8', errors='ignore')

def get_new_filename():
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    return os.path.join(OUTPUT_FOLDER, f"sensores_{timestamp}.csv")

# SERVIDOR UDP

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))

print(f"[*] Servidor UDP escuchando en el puerto {UDP_PORT}")
print(f"[*] Guardando en carpeta: {OUTPUT_FOLDER}")
print("[*] Esperando paquetes encriptados...")

rows_count = 0
current_filename = get_new_filename()
csv_file = open(current_filename, mode='w', newline='', encoding='utf-8')
csv_writer = csv.writer(csv_file)
csv_writer.writerow(["Sensor", "Trama_Hex", "Latencia_Lectura_us", "Latencia_Ensamblado_us", "EstadoTx", "Valor_1", "Unidad_1", "Valor_2", "Unidad_2", "Timestamp_Recepcion"])

try:
    while True:
        data, addr = sock.recvfrom(1024) # Recibir paquete UDP
        
        # Desencriptar la trama recibida
        try:
            texto_desencriptado = decrypt_payload(data)
            # El ESP32 enviará un string separado por comas
            if "," in texto_desencriptado:
                fila = texto_desencriptado.split(",")
                # Agregar marca de tiempo de recepcion para calcular Throughput
                fila.append(datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f"))
                csv_writer.writerow(fila)
                csv_file.flush()
                
                print(f"[{addr[0]}] Recibido: {texto_desencriptado}")
                
                rows_count += 1
                #Crea nueva tabla cada 50 000 envios
                if rows_count >= MAX_ROWS_PER_FILE:
                    csv_file.close()
                    print(f"\n[*] Límite de {MAX_ROWS_PER_FILE} alcanzado. Creando nuevo archivo.")
                    current_filename = get_new_filename()
                    csv_file = open(current_filename, mode='w', newline='', encoding='utf-8')
                    csv_writer = csv.writer(csv_file)
                    csv_writer.writerow(["Sensor", "Trama_Hex", "Latencia_Lectura_us", "Latencia_Ensamblado_us", "EstadoTx", "Valor_1", "Unidad_1", "Valor_2", "Unidad_2", "Timestamp_Recepcion"])
                    rows_count = 0

        except Exception as e:
            print(f"[!] Error al procesar paquete de {addr[0]}: {e}")

except KeyboardInterrupt:
    print("\n[*] Servidor detenido por el usuario.")
    csv_file.close()
