
# 1. Eliminar la libreria de trabajo actual si existe, y crear una limpia
if {[file exists work]} {
    vdel -all
}
vlib work
vmap work work

# 2. Compilar los archivos fuente RTL y el Testbench con flags de Cobertura
# Explicacion de Flags +cover=
# b: Branch (Ramificaciones/Arcos)
# c: Condition (Condicionales booleanas)
# e: Expression (Expresiones combinacionales)
# f: FSM (Reconocimiento automatico de maquinas de estado y transiciones)
# s: Statement (Lineas de codigo visitadas)
echo "Compilando modulo de memoria..."
vlog memory_and_framer.v

echo "Compilando modulo de la Maquina de Estados (FSM TMR)..."
vlog framer_fsm_tmr.v

echo "Compilando el Entorno de Testbench Dirigido..."
vlog tb_fsm_coverage.v

# 3. Lanzar el simulador habilitando el motor de cobertura de codigo
# Nota: +acc garantiza que las senales esten visibles en los waveform
echo "Invocando vsim sin motor de cobertura (licencia no disponible)..."
vsim -voptargs="+acc" work.tb_fsm_coverage

# 4. Configuracion visual de la herramienta (Waveforms)
view wave

# - Señales del Sistema
add wave -noupdate -divider "Reloj y Reset"
add wave -noupdate -color Gold /tb_fsm_coverage/clk_50M
add wave -noupdate -color Red /tb_fsm_coverage/rst_n

# - Estímulos inyectados (Inputs a la FSM)
add wave -noupdate -divider "Estímulos (Inyeccion Manual)"
add wave -noupdate -color Yellow /tb_fsm_coverage/data_ready_100k
add wave -noupdate -radix hex /tb_fsm_coverage/payload_data
add wave -noupdate -color Orange /tb_fsm_coverage/tx_busy

# - Estados de la Maquina Tolerante a Fallos (TMR)
add wave -noupdate -divider "Registros de Estado FSM (TMR)"
add wave -noupdate -radix unsigned /tb_fsm_coverage/dut_fsm/state_A
add wave -noupdate -radix unsigned /tb_fsm_coverage/dut_fsm/state_B
add wave -noupdate -radix unsigned /tb_fsm_coverage/dut_fsm/state_C
add wave -noupdate -color Cyan -radix unsigned /tb_fsm_coverage/dut_fsm/voted_state

# - Salidas de Control
add wave -noupdate -divider "Senales de Control Generadas"
add wave -noupdate /tb_fsm_coverage/we_ram
add wave -noupdate /tb_fsm_coverage/sel_rom
add wave -noupdate /tb_fsm_coverage/load_tx
add wave -noupdate -radix unsigned /tb_fsm_coverage/ptr
add wave -noupdate /tb_fsm_coverage/update_checksum

# - Transmision de Memoria (Datos Resultantes)
add wave -noupdate -divider "Datos Segmentados (ROM/RAM/CHK)"
add wave -noupdate -color Magenta -radix hex /tb_fsm_coverage/data_out
add wave -noupdate -color Magenta -radix hex /tb_fsm_coverage/checksum

# 5. Formatear la vista
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {4000 ns}

# 6. Ejecutar toda la bateria de pruebas hasta que $finish detenga la simulacion
echo "Iniciando corrida temporal de vectores de prueba..."
run -all

# 7. (Reportes de cobertura omitidos por falta de licencia)

echo "--------------------------------------------------------"
echo ">> SIMULACION COMPLETADA EXITOSAMENTE <<"
echo "Revise la consola y la ventana Waveforms para verificar que la FSM pase los 4 Casos."
echo "--------------------------------------------------------"
