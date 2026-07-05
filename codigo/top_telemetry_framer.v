// Ensamblador de Tramas de Telemetría (Top Module)
// Arquitectura determinista, tolerante a fallos (TMR) para misiones satelitales 1U

module top_telemetry_framer (
    input wire clk_50M,
    input wire rst_n,
    inout wire i2c_sda,
    output wire i2c_scl,
    output wire uart_tx
);

    // Relojes
    wire clk_100k;
    wire clk_uart;

    // Señales internas
    wire data_ready;
    wire [191:0] payload_data;
    wire [4:0] mem_ptr;
    wire sel_rom, we_ram, load_tx;
    wire clear_chk, update_chk, send_chk;
    wire [7:0] data_from_mem, checksum_val;
    wire tx_busy;
    
    wire [7:0] data_to_uart;

    // Instancia del divisor de reloj
    clock_divider clk_div_inst (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .clk_100k(clk_100k),
        .clk_uart(clk_uart)
    );

    // Instancia del Master I2C
    i2c_master_sensor i2c_master_inst (
        .clk_100k(clk_100k),
        .rst_n(rst_n),
        .scl(i2c_scl),
        .sda(i2c_sda),
        .data_ready(data_ready),
        .payload_data(payload_data)
    );

    // Instancia del sistema de memoria
    memory_and_framer mem_framer_inst (
        .clk(clk_50M),
        .rst_n(rst_n),
        .addr(mem_ptr),
        .sel_rom(sel_rom),
        .we_ram(we_ram),
        .payload_data(payload_data),
        .clear_checksum(clear_chk),
        .update_checksum(update_chk),
        .data_out(data_from_mem),
        .checksum(checksum_val)
    );

    // Multiplexor de salida final hacia la UART
    assign data_to_uart = send_chk ? checksum_val : data_from_mem;

    // Instancia de la Máquina de Estados Gobernadora (TMR)
    framer_fsm_tmr fsm_tmr_inst (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .data_ready_100k(data_ready),
        .tx_busy(tx_busy),
        .we_ram(we_ram),
        .sel_rom(sel_rom),
        .load_tx(load_tx),
        .ptr(mem_ptr),
        .clear_checksum(clear_chk),
        .update_checksum(update_chk),
        .send_checksum(send_chk)
    );

    // Instancia del Transmisor UART
    uart_tx_module uart_tx_inst (
        .clk_uart(clk_uart),
        .rst_n(rst_n),
        .tx_start(load_tx),
        .data_in(data_to_uart),
        .tx_pin(uart_tx),
        .tx_busy(tx_busy)
    );

endmodule
