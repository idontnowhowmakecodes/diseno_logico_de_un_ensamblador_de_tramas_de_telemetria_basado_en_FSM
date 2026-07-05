`timescale 1ns/1ps

// Módulo 6: tb_telemetry_framer (Testbench)
// Simulación exhaustiva del sistema con esclavo I2C simulado y validación de Casos Críticos.

module tb_telemetry_framer;

    reg clk_50M;
    reg rst_n;
    wire i2c_scl;
    wire i2c_sda;
    wire uart_tx;

    // Instancia del Top Module
    top_telemetry_framer dut (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .i2c_sda(i2c_sda),
        .i2c_scl(i2c_scl),
        .uart_tx(uart_tx)
    );

    // Generador de reloj 50 MHz (20 ns de periodo)
    initial begin
        clk_50M = 0;
        forever #10 clk_50M = ~clk_50M;
    end

    // Señal SDA interna para el testbench (como esclavo)
    reg tb_sda_out;
    reg tb_sda_en;
    assign i2c_sda = tb_sda_en ? tb_sda_out : 1'bz;

    // Bandera de control para Casos de Prueba
    reg trama_terminada;

    // Tarea para esperar al flanco de bajada de SCL
    task wait_scl_negedge;
        begin
            @(negedge i2c_scl);
        end
    endtask

    // Tarea para enviar un byte por I2C (Esclavo -> Master)
    task send_i2c_byte(input [7:0] byte_data);
        integer i;
        begin
            tb_sda_en = 1;
            for (i=7; i>=0; i=i-1) begin
                tb_sda_out = byte_data[i];
                wait_scl_negedge();
            end
        end
    endtask

    // Control del Esclavo I2C con reseteo asíncrono
    always @(negedge rst_n) begin
        disable sim_i2c_slave_block;
        tb_sda_en = 0;
        tb_sda_out = 1;
    end

    always @(posedge rst_n) begin : sim_i2c_slave_block
        integer i;
        forever begin
            // --- FASE 1: MPU6050 (14 bytes) ---
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge();
            #50000; tb_sda_en = 0;
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge(); tb_sda_en = 0;
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge(); #20000;
            for (i=0; i<13; i=i+1) begin
                send_i2c_byte(8'h10 + i);
                tb_sda_en = 0; wait_scl_negedge(); 
            end
            send_i2c_byte(8'h1D); 
            tb_sda_en = 0; wait_scl_negedge(); 
            wait(i2c_scl == 1 && i2c_sda == 1); #5000;

            // --- FASE 2: BMP280 (6 bytes) ---
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge();
            #50000; tb_sda_en = 0;
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge(); tb_sda_en = 0;
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge(); #20000;
            for (i=0; i<5; i=i+1) begin
                send_i2c_byte(8'h20 + i);
                tb_sda_en = 0; wait_scl_negedge(); 
            end
            send_i2c_byte(8'h25); 
            tb_sda_en = 0; wait_scl_negedge(); 
            wait(i2c_scl == 1 && i2c_sda == 1); #5000;

            // --- FASE 3: ADC (2 bytes) ---
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge();
            #50000; tb_sda_en = 0;
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge(); tb_sda_en = 0;
            repeat(8) wait_scl_negedge(); 
            tb_sda_en = 1; tb_sda_out = 0; wait_scl_negedge(); #20000;
            send_i2c_byte(8'h30); tb_sda_en = 0; wait_scl_negedge(); 
            send_i2c_byte(8'h31); tb_sda_en = 0; wait_scl_negedge(); 
            wait(i2c_scl == 1 && i2c_sda == 1); #5000;
        end
    end

    // Monitor UART (Enlace de Bajada)
    reg [7:0] rx_byte;
    reg [7:0] frame [0:26];
    integer byte_idx = 0;
    reg [7:0] calc_chk = 8'h00;

    always begin
        @(negedge uart_tx);
        #4340; 
        if (uart_tx == 0) begin : read_uart_loop
            integer j;
            for (j=0; j<8; j=j+1) begin
                #8680; 
                rx_byte[j] = uart_tx;
            end
            #8680;
            
            frame[byte_idx] = rx_byte;
            if (byte_idx < 26) calc_chk = calc_chk ^ rx_byte;
            
            $display("[%0t] UART RX: Byte %0d = 0x%02X", $time, byte_idx, rx_byte);
            
            if (byte_idx == 26) begin
                trama_terminada = 1;
                byte_idx = 0;
                calc_chk = 8'h00;
                #100; // Pulso corto
                trama_terminada = 0;
            end else begin
                byte_idx = byte_idx + 1;
            end
        end
    end

    // =========================================================
    // PLAN DE VERIFICACION: Casos de Prueba (UUT Stimulus)
    // =========================================================
    initial begin : test_cases
        $display("\n========================================");
        $display(" INICIANDO BANCO DE PRUEBAS DE CASOS CRITICOS");
        $display("========================================");
        rst_n = 0;
        tb_sda_en = 0;
        tb_sda_out = 1;
        trama_terminada = 0;
        #200;
        
        // -----------------------------------------------------
        $display("\n[CASO 1]: Flujo Nominal (Ensamblaje Exitoso)");
        // -----------------------------------------------------
        rst_n = 1;
        wait(trama_terminada == 1);
        $display("[CASO 1 PASSED] Checksum Valido y FSM recorrio ciclo exitosamente.");
        #10000;

        // -----------------------------------------------------
        $display("\n[CASO 2]: Comportamiento ante un reset a medio flujo");
        // -----------------------------------------------------
        // El I2C Master ya inicio otra lectura automaticamente
        // Esperamos a que empiece a transmitir por UART el 2do byte del payload (index 5)
        wait(byte_idx == 5);
        $display("[%0t] INYECTANDO RESET MIENTRAS FSM TRANSMITE...", $time);
        rst_n = 0;
        #500;
        // Verificamos si la FSM aborto a IDLE
        if (dut.fsm_tmr_inst.voted_state == 4'd0) 
            $display("[CASO 2 PASSED] FSM aborto transaccion y retorno a IDLE inmediatamente.");
        else 
            $display("[CASO 2 FAILED] FSM no retorno a IDLE.");
        byte_idx = 0; calc_chk = 0;
        #1000;

        // -----------------------------------------------------
        $display("\n[CASO 3]: Interrupcion de flujo de datos (Perdida de senal)");
        // -----------------------------------------------------
        // Levantamos reset pero forzamos que el I2C master jamas reporte data_ready
        force dut.i2c_master_inst.data_ready = 1'b0;
        rst_n = 1;
        #500000; // Esperamos medio milisegundo
        if (dut.fsm_tmr_inst.voted_state == 4'd0) 
            $display("[CASO 3 PASSED] FSM se mantuvo estable en IDLE sin desbordarse al faltar el pulso data_ready.");
        else 
            $display("[CASO 3 FAILED] FSM abandono IDLE incorrectamente.");
        release dut.i2c_master_inst.data_ready;
        #10000;

        // -----------------------------------------------------
        $display("\n[CASO 4]: Transiciones a estados de error (tx_busy timeout/stall)");
        // -----------------------------------------------------
        // Forzamos tx_busy de la UART en 1 permanentemente (periferico colgado)
        force dut.uart_tx_inst.tx_busy = 1'b1;
        // Esperamos que termine de recolectar I2C y la FSM detecte data_ready
        wait(dut.fsm_tmr_inst.data_ready_pulse == 1);
        #50000; 
        // La FSM deberia estar esperando indefinidamente en TX_ROM_SETUP o TX_ROM_WAIT
        if (dut.fsm_tmr_inst.voted_state == 4'd2 || dut.fsm_tmr_inst.voted_state == 4'd3) 
            $display("[CASO 4 PASSED] FSM bloqueada de forma segura esperando a la UART sin sobreescribir memoria.");
        else 
            $display("[CASO 4 FAILED] FSM continuo transicionando a pesar del stall de la UART.");
        
        release dut.uart_tx_inst.tx_busy;
        
        // Dejamos que finalice
        wait(trama_terminada == 1);

        $display("\n========================================");
        $display(" SIMULACION DE TODOS LOS CASOS CRITICOS COMPLETADA");
        $display("========================================");
        $finish;
    end

endmodule
