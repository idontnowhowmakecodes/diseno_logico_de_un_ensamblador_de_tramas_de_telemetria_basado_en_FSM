// Módulo 5: uart_tx_module (Enlace de Bajada)
// Transmisor serial asíncrono (8 bits de datos, sin paridad, 1 bit de parada)
// Gobernada por clk_uart (115200 Hz)

module uart_tx_module (
    input wire clk_uart,
    input wire rst_n,
    input wire tx_start,
    input wire [7:0] data_in,
    output reg tx_pin,
    output reg tx_busy
);

    reg [9:0] shift_reg;  // 1 Start bit + 8 Data bits + 1 Stop bit
    reg [3:0] bit_idx;    // Indice de bit a enviar

    always @(posedge clk_uart or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'h3FF; // Línea inactiva (Alto)
            bit_idx   <= 4'd0;
            tx_busy   <= 1'b0;
            tx_pin    <= 1'b1;
        end else begin
            if (tx_start && !tx_busy) begin
                // Carga la trama UART: Stop (1), Data, Start (0)
                shift_reg <= {1'b1, data_in, 1'b0}; 
                tx_busy   <= 1'b1;
                bit_idx   <= 4'd0;
            end else if (tx_busy) begin
                // Desplazamiento a la derecha, enviando LSB primero (como exige UART)
                tx_pin    <= shift_reg[0];
                shift_reg <= {1'b1, shift_reg[9:1]};
                
                if (bit_idx == 4'd9) begin
                    tx_busy <= 1'b0; // Finalizó la transmisión
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                end
            end else begin
                // Mantiene el pin en alto cuando está inactivo
                tx_pin <= 1'b1;
            end
        end
    end

endmodule
