`timescale 1ns/1ps

// Módulo 6: tb_telemetry_framer (Testbench)
// Simulación exhaustiva del sistema con esclavo I2C simulado y monitor UART.

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

    // Inicialización
    initial begin
        rst_n = 0;
        tb_sda_en = 0;
        tb_sda_out = 1;
        #100;
        rst_n = 1;
    end

    // Tarea para esperar al flanco de bajada de SCL (momento donde el esclavo cambia los datos)
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

    // Simulación del comportamiento del esclavo I2C (con latencias solicitadas)
    initial begin
        wait(rst_n == 1);
        forever begin
            // --- 1. Address Write (0xA6) ---
            repeat(8) wait_scl_negedge(); // Saltar los 8 bits de addr de escritura
            
            // Enviar ACK1 (Latencia inyectada para probar robustez del master)
            tb_sda_en = 1; tb_sda_out = 0; 
            wait_scl_negedge();
            
            // Latencia simulada (Hold Time reteniendo el bus antes de liberar)
            #50000;
            tb_sda_en = 0; // Soltar para que Master escriba REG

            // --- 2. Register Write (0x0D) ---
            repeat(8) wait_scl_negedge(); // Saltar 8 bits del registro
            
            // Enviar ACK2
            tb_sda_en = 1; tb_sda_out = 0;
            wait_scl_negedge();
            tb_sda_en = 0;

            // --- 3. Repeated Start & Address Read (0xA7) ---
            repeat(8) wait_scl_negedge(); // Saltar 8 bits addr de lectura
            
            // Enviar ACK3
            tb_sda_en = 1; tb_sda_out = 0;
            wait_scl_negedge();
            
            // Latencia simulada antes de empezar a enviar el payload
            #20000;

            // --- 4. Enviar Byte 1 (0x1A) ---
            send_i2c_byte(8'h1A);
            tb_sda_en = 0; // Soltar para leer ACK del master
            wait_scl_negedge(); 

            // --- 5. Enviar Byte 2 (0x2B) ---
            send_i2c_byte(8'h2B);
            tb_sda_en = 0;
            wait_scl_negedge(); 

            // --- 6. Enviar Byte 3 (0x3C) ---
            send_i2c_byte(8'h3C);
            tb_sda_en = 0;
            wait_scl_negedge(); // Master debe dar NACK y luego STOP
            
            $display("[%0t] Sensor I2C Esclavo: Transmision completada.", $time);
            
            // Esperar a que el bus vuelva a idle (SCL y SDA altos)
            wait(i2c_scl == 1 && i2c_sda == 1);
            // Pequeño retardo para asegurar que el STOP se procese
            #5000;
        end
    end

    // Monitor UART (Enlace de Bajada)
    reg [7:0] rx_byte;
    reg [7:0] frame [0:12];
    integer byte_idx = 0;
    reg [7:0] calc_chk = 8'h00;

    always begin
        // Esperar Start Bit (Flanco de bajada en uart_tx)
        @(negedge uart_tx);
        
        // Esperar mitad de bit a 115200 bps (1/115200 = 8.68 us -> 8680 ns)
        #4340; 
        if (uart_tx == 0) begin : read_uart_loop
            // Leer 8 bits de datos (LSB primero)
            integer j;
            for (j=0; j<8; j=j+1) begin
                #8680; // Esperar un periodo de bit completo
                rx_byte[j] = uart_tx;
            end
            
            // Esperar Stop bit
            #8680;
            
            frame[byte_idx] = rx_byte;
            
            // Computar checksum (excepto para el último byte que es el propio checksum)
            if (byte_idx < 12) begin
                calc_chk = calc_chk ^ rx_byte;
            end
            
            $display("[%0t] UART RX: Byte %0d = 0x%02X", $time, byte_idx, rx_byte);
            
            if (byte_idx == 12) begin
                $display("========================================");
                $display("           TRAMA COMPLETADA");
                $display("========================================");
                $display("Bytes de Payload I2C: 0x%02X, 0x%02X, 0x%02X", frame[4], frame[5], frame[6]);
                $display("Checksum Calculado  : 0x%02X", calc_chk);
                $display("Checksum Recibido   : 0x%02X", frame[12]);
                if (calc_chk == frame[12])
                    $display("Resultado: EXITO (Checksum correcto)");
                else
                    $display("Resultado: FALLO (Checksum incorrecto)");
                $display("========================================");
                $finish;
            end
            byte_idx = byte_idx + 1;
        end
    end

endmodule
