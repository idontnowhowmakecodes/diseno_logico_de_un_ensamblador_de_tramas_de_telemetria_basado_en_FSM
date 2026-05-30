// ---- MÓDULO PRINCIPAL ----
module top_system (
    input wire clk,
    input wire rst_n,
    input wire I2C_RDY,
    input wire UART_BUSY,        // Señal de espera externa
    input wire [2:0] input_data, // Datos entrantes
    output wire tx_serial        // Salida del registro de desplazamiento
);
    wire [3:0] ptr;
    wire we_ram, sel_rom, load_tx, tx_busy;
    wire [7:0] mem_data_out;

    // Instanciación de la Unidad de Control (FSM)
    fsm_control control_unit (
        .clk(clk),
        .rst_n(rst_n),
        .I2C_RDY(I2C_RDY),
        // El FSM esperará tanto al shift register interno como al UART externo
        .tx_busy(tx_busy | UART_BUSY), 
        .we_ram(we_ram),
        .sel_rom(sel_rom),
        .load_tx(load_tx),
        .ptr(ptr)
    );

    // Subsistema de Memoria
    memory_subsystem memories (
        .clk(clk),
        .addr(ptr),
        .we_ram(we_ram),
        .sel_rom(sel_rom),
        .data_in({5'b00000, input_data}), // Se hace el padding a 8 bits
        .data_out(mem_data_out)
    );

    // Registro de Desplazamiento (Transmisor)
    shift_transmitter datapath_tx (
        .clk(clk),
        .rst_n(rst_n),
        .load(load_tx),
        .data_in(mem_data_out),
        .tx_out(tx_serial),
        .busy(tx_busy)
    );
endmodule

// ---- MÓDULO FSM ----
module fsm_control (
    input wire clk,
    input wire rst_n,
    input wire I2C_RDY,
    input wire tx_busy,
    output reg we_ram,
    output reg sel_rom,
    output reg load_tx,
    output reg [3:0] ptr
);
    // Estados rediseñados para soportar los bucles de envío
    localparam IDLE         = 3'd0,
               WRITE_RAM    = 3'd1,
               TX_ROM_SETUP = 3'd2,
               TX_ROM_WAIT  = 3'd3,
               TX_RAM_SETUP = 3'd4,
               TX_RAM_WAIT  = 3'd5;

    reg [2:0] state, next_state;
    reg [3:0] next_ptr;
    
    // Configuración del tamaño de la trama (Ejemplo: 3 bytes ROM, 8 bytes RAM)
    localparam MAX_ROM = 4'd2; // Direcciones 0 a 2
    localparam MAX_RAM = 4'd7; // Direcciones 0 a 7

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ptr <= 4'd0;
        end else begin
            state <= next_state;
            ptr <= next_ptr;
        end
    end

    always @(*) begin
        // Valores por defecto para evitar latches
        next_state = state;
        next_ptr = ptr;
        we_ram = 1'b0;
        sel_rom = 1'b0;
        load_tx = 1'b0;

        case (state)
            IDLE: begin
                if (I2C_RDY) begin
                    next_ptr = 4'd0; 
                    next_state = WRITE_RAM;
                end
            end
            
            WRITE_RAM: begin
                we_ram = 1'b1;   // Escribe el dato de entrada en la RAM[0]
                next_ptr = 4'd0; // Reiniciamos el puntero para empezar a leer la ROM
                next_state = TX_ROM_SETUP;
            end
            
            // --- BUCLE 1: ENVIAR ENCABEZADO (ROM) ---
            TX_ROM_SETUP: begin
                sel_rom = 1'b1;  // Selecciona memoria ROM
                load_tx = 1'b1;  // Ordena al Shift Register cargar el dato
                next_state = TX_ROM_WAIT;
            end
            
            TX_ROM_WAIT: begin
                sel_rom = 1'b1;
                if (!tx_busy) begin // Espera a que termine de desplazar los 8 bits
                    if (ptr == MAX_ROM) begin
                        next_ptr = 4'd0; // ¡Clave! Reiniciamos el puntero a 0 para la RAM
                        next_state = TX_RAM_SETUP;
                    end else begin
                        next_ptr = ptr + 1'b1; // Avanza a la siguiente dirección de ROM
                        next_state = TX_ROM_SETUP;
                    end
                end
            end
            
            // --- BUCLE 2: ENVIAR PAYLOAD (RAM) ---
            TX_RAM_SETUP: begin
                sel_rom = 1'b0;  // Selecciona memoria RAM
                load_tx = 1'b1;  
                next_state = TX_RAM_WAIT;
            end
            
            TX_RAM_WAIT: begin
                sel_rom = 1'b0;
                if (!tx_busy) begin
                    if (ptr == MAX_RAM) begin
                        next_state = IDLE; // Terminó toda la trama, vuelve a inicio
                    end else begin
                        next_ptr = ptr + 1'b1;
                        next_state = TX_RAM_SETUP;
                    end
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
endmodule

// ---- SUBSISTEMA DE MEMORIA ----
module memory_subsystem (
    input wire clk,
    input wire [3:0] addr,
    input wire we_ram,
    input wire sel_rom,
    input wire [7:0] data_in,
    output wire [7:0] data_out
);
    reg [7:0] ROM_banco [0:15];
    reg [7:0] RAM_banco [0:15];

    initial begin
        ROM_banco[0] = 8'hA5; // Header Byte 1
        ROM_banco[1] = 8'h5A; // Header Byte 2
        ROM_banco[2] = 8'hFF; // Header Byte 3
    end

    always @(posedge clk) begin
        if (we_ram) begin
            RAM_banco[addr] <= data_in;
        end
    end

    // Lectura combinacional para que el dato esté disponible en el mismo ciclo para el Shift Register
    assign data_out = sel_rom ? ROM_banco[addr] : RAM_banco[addr];
endmodule

// ---- TRANSMISOR (SHIFT REGISTER) ----
module shift_transmitter (
    input wire clk,
    input wire rst_n,
    input wire load,
    input wire [7:0] data_in,
    output reg tx_out,
    output reg busy
);
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'h00;
            bit_cnt <= 3'd0;
            busy <= 1'b0;
            tx_out <= 1'b1; // Nivel alto cuando está inactivo (estándar UART)
        end else if (load) begin
            shift_reg <= data_in;
            bit_cnt <= 3'd0;
            busy <= 1'b1;
            tx_out <= data_in[7]; // MSB out
        end else if (busy) begin
            shift_reg <= {shift_reg[6:0], 1'b0};
            tx_out <= shift_reg[6];
            if (bit_cnt == 3'd7) begin
                busy <= 1'b0; // Libera la señal para que el FSM pase a la siguiente dirección
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end
endmodule
