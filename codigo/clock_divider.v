// Módulo 1: clock_divider (Reducción de Potencia Dinámica)
// Generador de relojes divididos a partir del reloj principal de 50 MHz
// Se requiere para mantener compatibilidad con requerimientos legacy y eficiencia energética.

module clock_divider (
    input wire clk_50M,
    input wire rst_n,
    output reg clk_100k,
    output reg clk_uart
);

    // Contadores para división de frecuencia
    // Para 100 kHz: 50 MHz / 100 kHz = 500 ciclos. Toggle cada 250 ciclos.
    reg [8:0] cnt_100k;
    
    // Para 115200 Hz: 50 MHz / 115200 = 434.02 ciclos. Toggle cada 217 ciclos.
    reg [8:0] cnt_uart;

    // Generación del reloj de 100 kHz para I2C
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            cnt_100k <= 9'd0;
            clk_100k <= 1'b0;
        end else begin
            if (cnt_100k == 9'd249) begin
                cnt_100k <= 9'd0;
                clk_100k <= ~clk_100k;
            end else begin
                cnt_100k <= cnt_100k + 1'b1;
            end
        end
    end

    // Generación del reloj de 115200 Hz para muestreo/transmisión de UART
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            cnt_uart <= 9'd0;
            clk_uart <= 1'b0;
        end else begin
            if (cnt_uart == 9'd216) begin
                cnt_uart <= 9'd0;
                clk_uart <= ~clk_uart;
            end else begin
                cnt_uart <= cnt_uart + 1'b1;
            end
        end
    end

endmodule
