module shift_transmitter (
    input wire clk,
    input wire rst_n,
    input wire load,
    input wire [7:0] data_in,
    output reg tx_out,
    output reg busy
);
    reg [9:0] shift_reg; // 1 Start + 8 Datos + 1 Stop = 10 bits
    reg [3:0] bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'h3FF; // En reposo, la línea UART debe estar en Alto (1)
            bit_cnt <= 4'd0;
            busy <= 1'b0;
            tx_out <= 1'b1; 
        end else if (load && !busy) begin
            // Ensamblamos el formato UART: {Stop bit, Datos, Start bit}
            // En UART normalmente se envía primero el LSB.
            shift_reg <= {1'b1, data_in, 1'b0}; 
            bit_cnt <= 4'd0;
            busy <= 1'b1;
            tx_out <= 1'b0; // Envía inmediatamente el Start Bit (0)
        end else if (busy) begin
            shift_reg <= {1'b1, shift_reg[9:1]}; // Desplazamiento a la derecha (LSB out)
            tx_out <= shift_reg[1]; // Saca el bit de la cola
            if (bit_cnt == 4'd9) begin
                busy <= 1'b0; // Ha enviado los 10 bits, libera la señal tx_busy
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end
endmodule
