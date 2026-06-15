`timescale 1ns/1ps

// Módulo: tb_fsm_coverage
// Testbench Dirigido (Directed Testing) enfocado en lograr 100% de Cobertura RTL
// Permite inyectar casos de borde (reset a medio flujo, cuelgue de UART, ausencia de datos)
// al instanciar únicamente la Máquina de Estados (FSM) y la Memoria segmentada.

module tb_fsm_coverage;

    // Entradas al DUT
    reg clk_50M;
    reg rst_n;
    reg data_ready_100k;
    reg [23:0] payload_data;
    reg tx_busy;

    // Interconexión y Salidas de Control (Monitoreadas por el TB)
    wire we_ram;
    wire sel_rom;
    wire load_tx;
    wire [3:0] ptr;
    wire clear_checksum;
    wire update_checksum;
    wire send_checksum;

    // Salidas de Datos de Memoria
    wire [7:0] data_out;
    wire [7:0] checksum;

    // Instancia del Device Under Test 1: Lógica de Control y Gobernabilidad TMR
    framer_fsm_tmr dut_fsm (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .data_ready_100k(data_ready_100k),
        .tx_busy(tx_busy),
        .we_ram(we_ram),
        .sel_rom(sel_rom),
        .load_tx(load_tx),
        .ptr(ptr),
        .clear_checksum(clear_checksum),
        .update_checksum(update_checksum),
        .send_checksum(send_checksum)
    );

    // Instancia del Device Under Test 2: Memoria ROM/RAM y Calculador de Checksum
    memory_and_framer dut_mem (
        .clk(clk_50M),
        .rst_n(rst_n),
        .addr(ptr),
        .sel_rom(sel_rom),
        .we_ram(we_ram),
        .payload_data(payload_data),
        .clear_checksum(clear_checksum),
        .update_checksum(update_checksum),
        .data_out(data_out),
        .checksum(checksum)
    );

    // Reloj del Sistema: 50 MHz (T = 20ns)
    initial begin
        clk_50M = 0;
        forever #10 clk_50M = ~clk_50M;
    end

    // Tarea: Emulador Dinámico de UART
    // En lugar de esperar milisegundos reales por los baudios (115200bps), esta tarea emula
    // los pulsos de 'tx_busy' reaccionando instantáneamente a 'load_tx' para acelerar la simulación.
    task automatic emulate_uart_tx;
        begin
            // Esperar asercion de carga
            wait(load_tx == 1);
            @(posedge clk_50M); // Sincronizar al siguiente flanco de reloj
            tx_busy = 1;        // Levantar bandera (Transmisor Ocupado)
            
            // Simular un tiempo nominal de transmisión (Acelerado)
            #150; 
            
            @(posedge clk_50M); // Sincronizar
            tx_busy = 0;        // Bajar bandera (Transmisión Completada)
        end
    endtask

    // Control de Flujo Principal de la Batería de Pruebas (Test Suite)
    initial begin
        $display("---------------------------------------------------------");
        $display("INICIO DE TEST SUITE - COBERTURA FSM TMR");
        $display("---------------------------------------------------------");
        
        // Estado Seguro Inicial
        rst_n = 0;
        data_ready_100k = 0;
        payload_data = 24'h000000;
        tx_busy = 0;

        #200;
        rst_n = 1;
        #100;

        // =========================================================================
        // CASO DE PRUEBA 1: Flujo Nominal (Ensamblaje exitoso)
        // =========================================================================
        $display("[%0t ns] ---> EJECUTANDO CASO 1: Flujo Nominal de Datos", $time);
        
        // Inyectar datos de telemetría válidos
        payload_data = 24'hAA55CC;
        
        // Emular pulso de Trigger (Sincronizado al reloj de 100kHz en hardware físico, pero aquí manual)
        data_ready_100k = 1;
        #100;
        data_ready_100k = 0;
        
        // Emular la transmisión de los 13 Bytes (4 ROM + 8 RAM + 1 CHK)
        begin : caso_1_loop
            integer j;
            for(j=0; j<13; j=j+1) begin
                emulate_uart_tx();
            end
        end
        
        // Verificar retorno seguro a estado de Reposo
        wait(dut_fsm.voted_state == 4'd0); // IDLE
        $display("[%0t ns] [OK] Caso 1 superado (FSM retornó a IDLE).", $time);
        #200;


        // =========================================================================
        // CASO DE PRUEBA 2: Comportamiento ante Reset a medio flujo (Abort)
        // =========================================================================
        $display("[%0t ns] ---> EJECUTANDO CASO 2: Reset Asincrono durante transmision", $time);
        payload_data = 24'h112233;
        data_ready_100k = 1;
        #100;
        data_ready_100k = 0;

        // Avanzar la simulación hasta transmitir los primeros 3 bytes
        begin : caso_2_loop
            integer k;
            for(k=0; k<3; k=k+1) begin
                emulate_uart_tx();
            end
        end

        // Durante el inicio del 4to byte, inducir un pulso agresivo de Reset
        wait(load_tx == 1);
        #15; // Esperar poco tiempo antes del flanco negativo del clock (Asincrono)
        $display("[%0t ns]        >>! INYECTANDO FALLA: rst_n = 0 !<<", $time);
        rst_n = 0;
        tx_busy = 0; // Restaurar la UART colgada
        
        #100; // Mantener reset
        rst_n = 1; // Liberar reset
        #100;
        
        if (dut_fsm.voted_state == 4'd0 && ptr == 0) begin
            $display("[%0t ns] [OK] Caso 2 superado (Aborto exitoso, Punteros reiniciados).", $time);
        end else begin
            $display("[%0t ns] [ERROR] Caso 2 Fallo. FSM atrapada.", $time);
        end
        #200;


        // =========================================================================
        // CASO DE PRUEBA 3: Interrupción de flujo de datos (Pérdida de señal)
        // =========================================================================
        $display("[%0t ns] ---> EJECUTANDO CASO 3: Ausencia prolongada de stimuli (Timeout data_ready)", $time);
        
        // No se inyecta data_ready. Se espera tiempo prolongado.
        #1500; 
        
        if (dut_fsm.voted_state == 4'd0 && we_ram == 0 && load_tx == 0) begin
            $display("[%0t ns] [OK] Caso 3 superado (FSM bloqueada en IDLE sin emitir señales falsas).", $time);
        end else begin
            $display("[%0t ns] [ERROR] Caso 3 Fallo. Transición espuria detectada.", $time);
        end
        #200;


        // =========================================================================
        // CASO DE PRUEBA 4: Transiciones a error (tx_busy stall / cuelgue UART)
        // =========================================================================
        $display("[%0t ns] ---> EJECUTANDO CASO 4: Cuelgue del periferico UART (tx_busy = 1 fijo)", $time);
        
        payload_data = 24'hDEADBF;
        data_ready_100k = 1;
        #100;
        data_ready_100k = 0;

        // Esperar la primera señal de carga
        wait(load_tx == 1);
        @(posedge clk_50M);
        tx_busy = 1; // Subir bandera
        
        $display("[%0t ns]        >>! INYECTANDO FALLA: tx_busy estancado en '1' !<<", $time);
        // Mantener retenido por una cantidad absurda de ciclos para validar el self-loop condicional
        #3000;
        
        // Evaluar en qué estado se quedó atrapada. 3=TX_ROM_WAIT, 5=TX_RAM_WAIT, 7=TX_CHK_WAIT
        if (dut_fsm.voted_state == 4'd3 || dut_fsm.voted_state == 4'd5 || dut_fsm.voted_state == 4'd7) begin
            $display("[%0t ns] [OK] Caso 4 superado (FSM retiene estado en WAIT_TX sin desbordar memoria).", $time);
        end else begin
            $display("[%0t ns] [ERROR] Caso 4 Fallo. Estado incorrecto: %0d", $time, dut_fsm.voted_state);
        end
        
        // Recuperar la UART para que la simulación termine limpia
        tx_busy = 0;
        
        // Drenar los bytes restantes para finalizar transacción y volver a IDLE
        begin : drain_loop
            while (dut_fsm.voted_state != 4'd0) begin
                wait(load_tx == 1 || dut_fsm.voted_state == 4'd0);
                if (load_tx == 1) begin
                    @(posedge clk_50M); 
                    tx_busy = 1; 
                    #150; 
                    @(posedge clk_50M); 
                    tx_busy = 0;
                end
            end
        end
        
        #500;
        $display("---------------------------------------------------------");
        $display("SIMULACION DE COBERTURA FINALIZADA");
        $display("Verifique el 'Coverage Report' para confirmar 100%%");
        $display("---------------------------------------------------------");
        $finish;
    end

endmodule
