`timescale 1ns/1ps

module tb_top_system();
    reg clk;
    reg rst_n;
    reg I2C_RDY;
    reg UART_BUSY;
    reg [2:0] input_data;

    wire tx_serial;

    top_system dut (
        .clk(clk),
        .rst_n(rst_n),
        .I2C_RDY(I2C_RDY),
        .UART_BUSY(UART_BUSY),
        .input_data(input_data),
        .tx_serial(tx_serial)
    );

    always #10 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        I2C_RDY = 0;
        UART_BUSY = 0;
        input_data = 3'b000;

        #25 rst_n = 1;
        #20;

        // --- INGRESO MANUAL DE DATOS ---
        // Aquí es donde puedes jugar colocando el dato que quieras
        input_data = 3'b111; 
        
        // Simulamos un "clic" en el botón I2C_RDY para activar la lectura
        #20 I2C_RDY = 1; 
        #20 I2C_RDY = 0;

        // --- TIEMPO DE ESPERA DE LA TRANSMISIÓN ---
        // 3 bytes ROM + 8 bytes RAM = 11 bytes.
        // Cada byte toma 10 ciclos de reloj en UART 8N1 (10 * 20ns = 200ns).
        // 11 bytes * 200ns = 2200ns aprox.
        #2500;

        // --- SEGUNDO INGRESO DE DATOS (EJEMPLO) ---
        // Después de terminar de transmitir la trama, probamos ingresar otro dato
        input_data = 3'b111;
        #20 I2C_RDY = 1; 
        #20 I2C_RDY = 0;

        #2500;

        $finish;
    end
endmodule
