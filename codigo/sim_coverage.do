
# 1. Eliminar la libreria de trabajo actual si existe, y crear una limpia
if {[file exists work]} {
    vdel -all
}
vlib work
vmap work work
vlog clock_divider.v memory_and_framer.v framer_fsm_tmr.v i2c_master_sensor.v uart_tx_module.v top_telemetry_framer.v tb_telemetry_framer.v
vsim -voptargs="+acc" work.tb_telemetry_framer

# BANNER: Fase
add wave -group "Fase de Prueba" -position insertpoint -color "Yellow" -radix unsigned sim:/tb_telemetry_framer/case_number

# Grupo 1: Reloj y Control
add wave -group "Reloj y Control" -position insertpoint sim:/tb_telemetry_framer/clk_50M
add wave -group "Reloj y Control" -position insertpoint sim:/tb_telemetry_framer/rst_n
add wave -group "Reloj y Control" -position insertpoint -radix unsigned sim:/tb_telemetry_framer/dut/fsm_tmr_inst/voted_state
add wave -group "Reloj y Control" -position insertpoint sim:/tb_telemetry_framer/dut/fsm_tmr_inst/data_ready_pulse

# Grupo 2: Buses I2C
add wave -group "Buses I2C" -position insertpoint sim:/tb_telemetry_framer/i2c_scl
add wave -group "Buses I2C" -position insertpoint sim:/tb_telemetry_framer/i2c_sda
add wave -group "Buses I2C" -position insertpoint sim:/tb_telemetry_framer/dut/i2c_master_inst/data_ready
add wave -group "Buses I2C" -position insertpoint -radix unsigned sim:/tb_telemetry_framer/dut/i2c_master_inst/state

# Grupo 3: Transmision UART
add wave -group "Transmision UART" -position insertpoint sim:/tb_telemetry_framer/uart_tx
add wave -group "Transmision UART" -position insertpoint sim:/tb_telemetry_framer/dut/uart_tx_inst/tx_busy
add wave -group "Transmision UART" -position insertpoint sim:/tb_telemetry_framer/dut/fsm_tmr_inst/load_tx

# Grupo 4: Recepcion Monitor
add wave -group "Recepcion (Monitor)" -position insertpoint -radix hexadecimal sim:/tb_telemetry_framer/rx_byte
add wave -group "Recepcion (Monitor)" -position insertpoint -radix unsigned sim:/tb_telemetry_framer/byte_idx
add wave -group "Recepcion (Monitor)" -position insertpoint -radix hexadecimal sim:/tb_telemetry_framer/calc_chk
add wave -group "Recepcion (Monitor)" -position insertpoint sim:/tb_telemetry_framer/trama_terminada

run -all
wave zoom full
