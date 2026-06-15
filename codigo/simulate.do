# simulate.do
# Script TCL para automatizar la simulacion en ModelSim

# 1. Crear directorio de trabajo
vlib work

# 2. Compilar archivos del diseño
# Ajustar el orden para que las dependencias estén correctas
vlog clock_divider.v
vlog i2c_master_sensor.v
vlog framer_fsm_tmr.v
vlog memory_and_framer.v
vlog uart_tx_module.v
vlog top_telemetry_framer.v
vlog tb_telemetry_framer.v

# 3. Cargar el modulo top de simulacion (-voptargs=+acc evita que ModelSim oculte señales)
vsim -voptargs="+acc" work.tb_telemetry_framer

# 4. Configurar la ventana Wave
onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider "=== Reloj y Control ==="
add wave -noupdate -color Yellow /tb_telemetry_framer/clk_50M
add wave -noupdate -color Orange /tb_telemetry_framer/rst_n

add wave -noupdate -divider "=== Bus I2C ==="
add wave -noupdate -color Cyan /tb_telemetry_framer/i2c_scl
add wave -noupdate -color Cyan /tb_telemetry_framer/i2c_sda
add wave -noupdate -radix hexadecimal /tb_telemetry_framer/dut/i2c_inst/payload_data
add wave -noupdate -color Magenta /tb_telemetry_framer/dut/data_ready_wire

add wave -noupdate -divider "=== Transmision UART ==="
add wave -noupdate -color Green /tb_telemetry_framer/uart_tx
add wave -noupdate -radix hexadecimal /tb_telemetry_framer/dut/uart_inst/tx_data
add wave -noupdate /tb_telemetry_framer/dut/uart_inst/tx_busy

add wave -noupdate -divider "=== Recepcion (Testbench) ==="
add wave -noupdate -radix hexadecimal /tb_telemetry_framer/rx_byte
add wave -noupdate -radix unsigned /tb_telemetry_framer/byte_idx
add wave -noupdate -radix hexadecimal /tb_telemetry_framer/calc_chk

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# 5. Ejecutar hasta encontrar el $finish
run -all
wave zoom full
