#include "aes/esp_aes.h"
#include "driver/i2c.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "nvs_flash.h"
#include <lwip/netdb.h>
#include <stdio.h>
#include <string.h>

// CONFIGURACIÓN WIFI Y RED

#define WIFI_SSID "TU_SSID"
#define WIFI_PASS "TU_PASSWORD"
#define HOST_IP_ADDR "TU_IP" // Cambiar por la IP de tu PC
#define PORT 5005

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT BIT1
static EventGroupHandle_t s_wifi_event_group;
static int s_retry_num = 0;

// CONFIGURACIÓN CRIPTOGRÁFICA (AES-256-CBC)

static const unsigned char aes_key[] = "idntmkecodes_32bytes_long_key_12";
static const unsigned char aes_iv[] = "idntmkecodes_iv_";

// CONFIGURACIÓN HARDWARE I2C

#define I2C_MASTER_SDA_IO 8
#define I2C_MASTER_SCL_IO 9
#define I2C_MASTER_NUM 0
#define I2C_MASTER_FREQ_HZ 100000
#define I2C_MASTER_TX_BUF_DISABLE 0
#define I2C_MASTER_RX_BUF_DISABLE 0

#define BH1750_SENSOR_ADDR 0x23 // GY-302
#define BMP280_SENSOR_ADDR 0x76

// Cabeceras Estáticas de la Trama
#define SYNC_BYTE_1 0xAA
#define SYNC_BYTE_2 0x55
#define DEVICE_ID 0x01
#define PAYLOAD_LEN 0x08 // Longitud de los datos utiles de la trama

static const char *TAG = "MAIN";

// Socket global
int sock = -1;
struct sockaddr_in dest_addr;

// VARIABLES Y COMPENSACIÓN BMP280

uint16_t dig_T1;
int16_t dig_T2;
int16_t dig_T3;
uint16_t dig_P1;
int16_t dig_P2;
int16_t dig_P3;
int16_t dig_P4;
int16_t dig_P5;
int16_t dig_P6;
int16_t dig_P7;
int16_t dig_P8;
int16_t dig_P9;
int32_t t_fine;

void read_calibration_data(void) {
  uint8_t calib[24];
  uint8_t reg = 0x88;
  esp_err_t err =
      i2c_master_write_read_device(I2C_MASTER_NUM, BMP280_SENSOR_ADDR, &reg, 1,
                                   calib, 24, 1000 / portTICK_PERIOD_MS);
  if (err == ESP_OK) {
    dig_T1 = (calib[1] << 8) | calib[0];
    dig_T2 = (calib[3] << 8) | calib[2];
    dig_T3 = (calib[5] << 8) | calib[4];
    dig_P1 = (calib[7] << 8) | calib[6];
    dig_P2 = (calib[9] << 8) | calib[8];
    dig_P3 = (calib[11] << 8) | calib[10];
    dig_P4 = (calib[13] << 8) | calib[12];
    dig_P5 = (calib[15] << 8) | calib[14];
    dig_P6 = (calib[17] << 8) | calib[16];
    dig_P7 = (calib[19] << 8) | calib[18];
    dig_P8 = (calib[21] << 8) | calib[20];
    dig_P9 = (calib[23] << 8) | calib[22];
    ESP_LOGI(TAG, "Calibration data loaded successfully.");
  } else {
    ESP_LOGE(TAG, "Failed to read BMP280 calibration data.");
  }
}

double bmp280_compensate_T_double(int32_t adc_T) {
  double var1, var2, T;
  var1 = (((double)adc_T) / 16384.0 - ((double)dig_T1) / 1024.0) *
         ((double)dig_T2);
  var2 = ((((double)adc_T) / 131072.0 - ((double)dig_T1) / 8192.0) *
          (((double)adc_T) / 131072.0 - ((double)dig_T1) / 8192.0)) *
         ((double)dig_T3);
  t_fine = (int32_t)(var1 + var2);
  T = (var1 + var2) / 5120.0;
  return T;
}

double bmp280_compensate_P_double(int32_t adc_P) {
  double var1, var2, p;
  var1 = ((double)t_fine / 2.0) - 64000.0;
  var2 = var1 * var1 * ((double)dig_P6) / 32768.0;
  var2 = var2 + var1 * ((double)dig_P5) * 2.0;
  var2 = (var2 / 4.0) + (((double)dig_P4) * 65536.0);
  var1 = (((double)dig_P3) * var1 * var1 / 524288.0 + ((double)dig_P2) * var1) /
         524288.0;
  var1 = (1.0 + var1 / 32768.0) * ((double)dig_P1);
  if (var1 == 0.0) {
    return 0.0; // avoid exception caused by division by zero
  }
  p = 1048576.0 - (double)adc_P;
  p = (p - (var2 / 4096.0)) * 6250.0 / var1;
  var1 = ((double)dig_P9) * p * p / 2147483648.0;
  var2 = p * ((double)dig_P8) / 32768.0;
  p = p + (var1 + var2 + ((double)dig_P7)) / 16.0;
  return p / 100.0; // Return in hPa
}

// Inicializar el bus I2C
static esp_err_t i2c_master_init(void) {
  int i2c_master_port = I2C_MASTER_NUM;
  i2c_config_t conf = {
      .mode = I2C_MODE_MASTER,
      .sda_io_num = I2C_MASTER_SDA_IO,
      .sda_pullup_en = GPIO_PULLUP_ENABLE,
      .scl_io_num = I2C_MASTER_SCL_IO,
      .scl_pullup_en = GPIO_PULLUP_ENABLE,
      .master.clk_speed = I2C_MASTER_FREQ_HZ,
  };
  esp_err_t err = i2c_param_config(i2c_master_port, &conf);
  if (err != ESP_OK)
    return err;
  return i2c_driver_install(i2c_master_port, conf.mode,
                            I2C_MASTER_RX_BUF_DISABLE,
                            I2C_MASTER_TX_BUF_DISABLE, 0);
}

// Calcular Checksum (XOR básico)
uint8_t calculate_checksum(uint8_t *data, int length) {
  uint8_t checksum = 0;
  for (int i = 0; i < length; i++) {
    checksum ^= data[i];
  }
  return checksum;
}

// Función auxiliar para imprimir la trama en Hexadecimal
void format_hex_trama(uint8_t *buffer, int len, char *out_str) {
  out_str[0] = '\0';
  char temp[4];
  for (int i = 0; i < len; i++) {
    sprintf(temp, "%02X", buffer[i]);
    strcat(out_str, temp);
  }
}

// Enviar paquete UDP encriptado
void send_udp_encrypted(const char *payload) {
  if (sock < 0)
    return;

  size_t payload_len = strlen(payload);
  // Padding manual a un múltiplo de 16 bytes con ceros (0x00)
  size_t padded_len = ((payload_len / 16) + 1) * 16;
  unsigned char *padded_input = calloc(padded_len, 1);
  unsigned char *encrypted_output = calloc(padded_len, 1);

  memcpy(padded_input, payload, payload_len);

  esp_aes_context aes;
  esp_aes_init(&aes);
  esp_aes_setkey(&aes, aes_key, 256);

  // El IV se modifica durante la encriptación CBC, por lo que usamos una copia
  // temporal
  unsigned char iv_tmp[16];
  memcpy(iv_tmp, aes_iv, 16);

  esp_aes_crypt_cbc(&aes, ESP_AES_ENCRYPT, padded_len, iv_tmp, padded_input,
                    encrypted_output);
  esp_aes_free(&aes);

  int err = sendto(sock, encrypted_output, padded_len, 0,
                   (struct sockaddr *)&dest_addr, sizeof(dest_addr));
  if (err < 0) {
    ESP_LOGE(TAG, "Error enviando UDP: errno %d", errno);
  }

  free(padded_input);
  free(encrypted_output);
}

// ==========================================
// EVENTOS WIFI
// ==========================================
static void event_handler(void *arg, esp_event_base_t event_base,
                          int32_t event_id, void *event_data) {
  if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
  } else if (event_base == WIFI_EVENT &&
             event_id == WIFI_EVENT_STA_DISCONNECTED) {
    if (s_retry_num < 10) {
      esp_wifi_connect();
      s_retry_num++;
      ESP_LOGI(TAG, "Reintentando conexión al AP...");
    } else {
      xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
    }
    ESP_LOGI(TAG, "Fallo al conectar al AP");
  } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    ESP_LOGI(TAG, "Obtuvo IP:" IPSTR, IP2STR(&event->ip_info.ip));
    s_retry_num = 0;
    xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
  }
}

void wifi_init_sta(void) {
  s_wifi_event_group = xEventGroupCreate();

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  esp_netif_create_default_wifi_sta();

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&cfg));

  esp_event_handler_instance_t instance_any_id;
  esp_event_handler_instance_t instance_got_ip;
  ESP_ERROR_CHECK(esp_event_handler_instance_register(
      WIFI_EVENT, ESP_EVENT_ANY_ID, &event_handler, NULL, &instance_any_id));
  ESP_ERROR_CHECK(esp_event_handler_instance_register(
      IP_EVENT, IP_EVENT_STA_GOT_IP, &event_handler, NULL, &instance_got_ip));

  wifi_config_t wifi_config = {
      .sta =
          {
              .ssid = WIFI_SSID,
              .password = WIFI_PASS,
              .threshold.authmode = WIFI_AUTH_WPA2_PSK,
          },
  };
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
  ESP_ERROR_CHECK(esp_wifi_start());

  ESP_LOGI(TAG, "wifi_init_sta finalizado.");

  EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group,
                                         WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
                                         pdFALSE, pdFALSE, portMAX_DELAY);

  if (bits & WIFI_CONNECTED_BIT) {
    ESP_LOGI(TAG, "Conectado al SSID:%s", WIFI_SSID);

    // Crear socket UDP
    dest_addr.sin_addr.s_addr = inet_addr(HOST_IP_ADDR);
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(PORT);
    sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);

  } else if (bits & WIFI_FAIL_BIT) {
    ESP_LOGI(TAG, "Fallo al conectar a SSID:%s", WIFI_SSID);
  } else {
    ESP_LOGE(TAG, "Evento inesperado");
  }
}

// Tarea principal
void app_main(void) {
  // Inicializar NVS
  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
      ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ret = nvs_flash_init();
  }
  ESP_ERROR_CHECK(ret);

  ESP_LOGI(TAG, "Inicializando WiFi...");
  wifi_init_sta();

  // Imprimir cabecera CSV localmente
  printf("Sensor,Trama_Hex,Latencia_Lectura_us,Latencia_Ensamblado_us,EstadoTx,"
         "Valor_1,Unidad_1,Valor_2,Unidad_2\n");

  // Inicialización del Hardware I2C
  esp_err_t i2c_err = i2c_master_init();
  if (i2c_err != ESP_OK) {
    ESP_LOGE(TAG, "Fallo al inicializar I2C");
  }

  // Despertar el BMP280 (Poner en Modo Normal)
  uint8_t bmp280_init_cmd[2] = {0xF4, 0x27};
  i2c_master_write_to_device(I2C_MASTER_NUM, BMP280_SENSOR_ADDR,
                             bmp280_init_cmd, 2, 1000 / portTICK_PERIOD_MS);

  // Leer datos de calibración del BMP280
  read_calibration_data();

  uint8_t data_bh1750[2] = {0};
  uint8_t data_bmp280[6] = {0};
  uint8_t tx_buffer[13];
  char hex_str[30];
  char csv_line[128];

  while (1) {
    // ==========================================
    // SENSOR 1: LECTURA GY-302 (BH1750)
    // ==========================================
    int64_t start_time = esp_timer_get_time();

    uint8_t cmd_bh = 0x10; // Modo de resolución alta continuo
    i2c_master_write_to_device(I2C_MASTER_NUM, BH1750_SENSOR_ADDR, &cmd_bh, 1,
                               1000 / portTICK_PERIOD_MS);
    vTaskDelay(pdMS_TO_TICKS(180)); // El sensor necesita ~180ms para medir

    esp_err_t err_bh =
        i2c_master_read_from_device(I2C_MASTER_NUM, BH1750_SENSOR_ADDR,
                                    data_bh1750, 2, 1000 / portTICK_PERIOD_MS);

    int64_t latencia_lectura_bh = esp_timer_get_time() - start_time;

    // Ensamblaje Trama BH1750
    start_time = esp_timer_get_time();
    tx_buffer[0] = SYNC_BYTE_1;
    tx_buffer[1] = SYNC_BYTE_2;
    tx_buffer[2] = DEVICE_ID;
    tx_buffer[3] = PAYLOAD_LEN;
    tx_buffer[4] = data_bh1750[0]; // Byte Alto Luz
    tx_buffer[5] = data_bh1750[1]; // Byte Bajo Luz
    memset(&tx_buffer[6], 0, 6);   // Relleno restante del payload
    tx_buffer[12] = calculate_checksum(tx_buffer, 12);
    int64_t latencia_ensamblado_bh = esp_timer_get_time() - start_time;

    format_hex_trama(tx_buffer, 13, hex_str);

    // Decodificar valor de luz BH1750
    float lux = err_bh == ESP_OK
                    ? ((float)((data_bh1750[0] << 8) | data_bh1750[1]) / 1.2f)
                    : 0.0f;

    // Formatear línea CSV con Valor y Unidad
    sprintf(csv_line, "BH1750,%s,%lld,%lld,%s,%.2f,Lux,,", hex_str,
            latencia_lectura_bh, latencia_ensamblado_bh,
            err_bh == ESP_OK ? "Exito" : "Fallo", lux);
    printf("%s\n", csv_line);

    // Enviar por WiFi (Encriptado)
    send_udp_encrypted(csv_line);

    // SENSOR 2: LECTURA BMP280
    start_time = esp_timer_get_time();

    uint8_t reg_bmp = 0xF7; // Registro inicial de datos crudos (Presión MSB)
    esp_err_t err_bmp = i2c_master_write_read_device(
        I2C_MASTER_NUM, BMP280_SENSOR_ADDR, &reg_bmp, 1, data_bmp280, 6,
        1000 / portTICK_PERIOD_MS);

    int64_t latencia_lectura_bmp = esp_timer_get_time() - start_time;

    // Ensamblaje Trama BMP280
    start_time = esp_timer_get_time();
    tx_buffer[0] = SYNC_BYTE_1;
    tx_buffer[1] = SYNC_BYTE_2;
    tx_buffer[2] = DEVICE_ID;
    tx_buffer[3] = PAYLOAD_LEN;
    memcpy(&tx_buffer[4], data_bmp280,
           6);         // Copiar 6 bytes de presión y temperatura
    tx_buffer[10] = 0; // Relleno
    tx_buffer[11] = 0; // Relleno
    tx_buffer[12] = calculate_checksum(tx_buffer, 12);
    int64_t latencia_ensamblado_bmp = esp_timer_get_time() - start_time;

    format_hex_trama(tx_buffer, 13, hex_str);

    // Decodificar valores físicos BMP280
    int32_t adc_P =
        (data_bmp280[0] << 12) | (data_bmp280[1] << 4) | (data_bmp280[2] >> 4);
    int32_t adc_T =
        (data_bmp280[3] << 12) | (data_bmp280[4] << 4) | (data_bmp280[5] >> 4);
    double temp = err_bmp == ESP_OK ? bmp280_compensate_T_double(adc_T) : 0.0;
    double press = err_bmp == ESP_OK ? bmp280_compensate_P_double(adc_P) : 0.0;

    // Formatear línea CSV con Valores y Unidades
    sprintf(csv_line, "BMP280,%s,%lld,%lld,%s,%.2f,C,%.2f,hPa", hex_str,
            latencia_lectura_bmp, latencia_ensamblado_bmp,
            err_bmp == ESP_OK ? "Exito" : "Fallo", temp, press);
    printf("%s\n", csv_line);

    // Enviar por WiFi (Encriptado)
    send_udp_encrypted(csv_line);

    vTaskDelay(pdMS_TO_TICKS(1820));
  }
}
