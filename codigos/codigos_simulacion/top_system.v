module top_system (
    input wire clk,
    input wire rst_n,
    input wire I2C_RDY,
    input wire UART_BUSY,        // Señal de espera externa
    input wire [2:0] input_data, // Datos entrantes
    output wire tx_serial        // Salida del registro de desplazamiento (Hacia el ESP32)
);
    wire [3:0] ptr;
    wire we_ram, sel_rom, load_tx, tx_busy;
    wire [7:0] mem_data_out;

    fsm_control control_unit (
        .clk(clk),
        .rst_n(rst_n),
        .I2C_RDY(I2C_RDY),
        .tx_busy(tx_busy | UART_BUSY), // Se detiene si el transmisor interno o externo están ocupados
        .we_ram(we_ram),
        .sel_rom(sel_rom),
        .load_tx(load_tx),
        .ptr(ptr)
    );

    memory_subsystem memories (
        .clk(clk),
        .addr(ptr),
        .we_ram(we_ram),
        .sel_rom(sel_rom),
        .data_in({5'b00000, input_data}), // Padding a 8 bits
        .data_out(mem_data_out)
    );

    shift_transmitter datapath_tx (
        .clk(clk),
        .rst_n(rst_n),
        .load(load_tx),
        .data_in(mem_data_out),
        .tx_out(tx_serial),
        .busy(tx_busy)
    );
endmodule
