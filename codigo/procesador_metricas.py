import os
import glob
import pandas as pd
from datetime import datetime

# Configuracion
FOLDER = "datos_historicos"
FRAME_TOTAL_BYTES = 13
PAYLOAD_BYTES = 8
BITS_PER_BYTE = 8

def main():
    print("      ANALIZADOR DE METRICAS DE TELEMETRIA        ")

    if not os.path.exists(FOLDER):
        print(f"[!] La carpeta '{FOLDER}' no existe. Asegurese de ejecutar el receptor primero.")
        return

    # Buscar el ultimo archivo CSV generado
    archivos = glob.glob(os.path.join(FOLDER, "*.csv"))
    if not archivos:
        print(f"[!] No hay archivos CSV en la carpeta '{FOLDER}'.")
        return

    # Ordenar por tiempo de modificacion y tomar el ultimo
    ultimo_archivo = max(archivos, key=os.path.getmtime)
    print(f"[*] Analizando archivo: {ultimo_archivo}")

    try:
        # Cargar CSV
        df = pd.read_csv(ultimo_archivo)
        
        # Eliminar filas corruptas
        df = df.dropna()

        total_tramas = len(df)
        if total_tramas < 2:
            print("[!] El archivo debe tener al menos 2 tramas para calcular throughput.")
            return

        print(f"\n[*] Total de tramas procesadas: {total_tramas}")

        # 1. Eficiencia de Trama
        # (Datos Utiles / Tamano Total) * 100
        eficiencia = (PAYLOAD_BYTES / FRAME_TOTAL_BYTES) * 100
        print(f"\n[1] Eficiencia de Trama:")
        print(f"    - Payload: {PAYLOAD_BYTES} bytes")
        print(f"    - Trama Total (con cabeceras/checksum): {FRAME_TOTAL_BYTES} bytes")
        print(f"    - Porcentaje de Eficiencia: {eficiencia:.2f} %")

        # Convertir latencias a numerico por seguridad
        df["Latencia_Lectura_us"] = pd.to_numeric(df["Latencia_Lectura_us"], errors='coerce')
        df["Latencia_Ensamblado_us"] = pd.to_numeric(df["Latencia_Ensamblado_us"], errors='coerce')

        # 2. Latencia de Ensamblado (Manejo en ROM/CPU)
        lat_ensamblado_avg = df["Latencia_Ensamblado_us"].mean()
        lat_ensamblado_min = df["Latencia_Ensamblado_us"].min()
        lat_ensamblado_max = df["Latencia_Ensamblado_us"].max()

        print(f"\n[2] Latencia de Ensamblado:")
        print(f"    - Promedio: {lat_ensamblado_avg:.2f} us")
        print(f"    - Minimo:   {lat_ensamblado_min:.2f} us")
        print(f"    - Maximo:   {lat_ensamblado_max:.2f} us")

        # 3. Tiempo de Acceso a Memoria (Latencia de Lectura I2C)
        lat_lectura_avg = df["Latencia_Lectura_us"].mean()
        lat_lectura_min = df["Latencia_Lectura_us"].min()
        lat_lectura_max = df["Latencia_Lectura_us"].max()

        print(f"\n[3] Tiempo de Acceso a Memoria (Lectura I2C):")
        print(f"    - Promedio: {lat_lectura_avg:.2f} us")
        print(f"    - Minimo:   {lat_lectura_min:.2f} us")
        print(f"    - Maximo:   {lat_lectura_max:.2f} us")

        # 4. Throughput de Transmision
        # Requiere la columna Timestamp_Recepcion
        if "Timestamp_Recepcion" in df.columns:
            # Convertir string a objetos datetime
            df["Timestamp_Recepcion"] = pd.to_datetime(df["Timestamp_Recepcion"])
            
            tiempo_inicio = df["Timestamp_Recepcion"].iloc[0]
            tiempo_fin = df["Timestamp_Recepcion"].iloc[-1]
            
            delta_tiempo = (tiempo_fin - tiempo_inicio).total_seconds()
            
            # Bits totales = cantidad_tramas * 13_bytes_por_trama * 8_bits
            bits_totales = total_tramas * FRAME_TOTAL_BYTES * BITS_PER_BYTE
            
            if delta_tiempo > 0:
                throughput_bps = bits_totales / delta_tiempo
                print(f"\n[4] Throughput de Transmision (UDP a receptor):")
                print(f"    - Ventana de tiempo: {delta_tiempo:.4f} segundos")
                print(f"    - Total Bits Tx:     {bits_totales} bits")
                print(f"    - Throughput Real:   {throughput_bps:.2f} bps")
            else:
                print("\n[!] Delta de tiempo es 0. Necesitamos recopilar mas datos.")
        else:
            print("\n[!] No se encontro la columna 'Timestamp_Recepcion' en el CSV. ")
            print("    Ejecute el ESP32 de nuevo con el script de recepcion modificado para medir throughput.")

    except Exception as e:
        print(f"[!] Error procesando el archivo: {e}")

if __name__ == "__main__":
    main()
