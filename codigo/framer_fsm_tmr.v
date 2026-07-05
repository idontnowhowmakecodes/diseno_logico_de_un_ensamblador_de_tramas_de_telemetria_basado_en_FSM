// Módulo 4: framer_fsm_tmr (Controlador Central de Alta Fiabilidad)
// Gobernador del sistema con mitigación SEU mediante Triple Redundancia Modular (TMR)

module framer_fsm_tmr (
    input wire clk_50M,
    input wire rst_n,
    input wire data_ready_100k,
    input wire tx_busy,
    output reg we_ram,
    output reg sel_rom,
    output reg load_tx,
    output reg [4:0] ptr,
    output reg clear_checksum,
    output reg update_checksum,
    output reg send_checksum
);

    // Sincronizador de 2 etapas para cruce de dominio (100kHz -> 50MHz)
    reg sync1_dr, sync2_dr, sync3_dr;
    wire data_ready_pulse;

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            sync1_dr <= 1'b0;
            sync2_dr <= 1'b0;
            sync3_dr <= 1'b0;
        end else begin
            sync1_dr <= data_ready_100k;
            sync2_dr <= sync1_dr;
            sync3_dr <= sync2_dr;
        end
    end
    
    assign data_ready_pulse = sync2_dr & ~sync3_dr;

    // Sincronizador para tx_busy (Cruce UART -> 50MHz)
    reg sync1_txb, sync2_txb, sync3_txb;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            sync1_txb <= 1'b0;
            sync2_txb <= 1'b0;
            sync3_txb <= 1'b0;
        end else begin
            sync1_txb <= tx_busy;
            sync2_txb <= sync1_txb;
            sync3_txb <= sync2_txb;
        end
    end
    wire txb_falling = ~sync2_txb & sync3_txb;
    wire txb_active = sync2_txb;

    // Estados
    localparam IDLE         = 4'd0,
               WRITE_RAM    = 4'd1,
               TX_ROM_SETUP = 4'd2,
               TX_ROM_WAIT  = 4'd3,
               TX_RAM_SETUP = 4'd4,
               TX_RAM_WAIT  = 4'd5,
               TX_CHK_SETUP = 4'd6,
               TX_CHK_WAIT  = 4'd7,
               DONE         = 4'd8;

    // Registros TMR con directivas de Quartus Prime
    reg [3:0] state_A /* synthesis preserve */;
    reg [3:0] state_B /* synthesis keep */;
    reg [3:0] state_C /* synthesis preserve */;
    
    reg [3:0] next_state;
    reg [4:0] ptr_reg, next_ptr;

    // Votador Mayoritario (Combinacional)
    wire [3:0] voted_state;
    assign voted_state = (state_A & state_B) | (state_B & state_C) | (state_A & state_C);

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            state_A <= IDLE;
            state_B <= IDLE;
            state_C <= IDLE;
            ptr_reg <= 5'd0;
        end else begin
            state_A <= next_state;
            state_B <= next_state;
            state_C <= next_state;
            ptr_reg <= next_ptr;
        end
    end

    always @(*) begin
        next_state = voted_state;
        next_ptr = ptr_reg;
        we_ram = 1'b0;
        sel_rom = 1'b0;
        load_tx = 1'b0;
        clear_checksum = 1'b0;
        update_checksum = 1'b0;
        send_checksum = 1'b0;
        ptr = ptr_reg;

        case (voted_state)
            IDLE: begin
                clear_checksum = 1'b1;
                if (data_ready_pulse) begin
                    next_ptr = 5'd0;
                    next_state = WRITE_RAM;
                end
            end

            WRITE_RAM: begin
                we_ram = 1'b1;
                next_ptr = 5'd0;
                next_state = TX_ROM_SETUP;
            end

            TX_ROM_SETUP: begin
                sel_rom = 1'b1;
                load_tx = 1'b1; // Mantenemos alto hasta que la UART responda
                if (txb_active) begin
                    next_state = TX_ROM_WAIT;
                end
            end

            TX_ROM_WAIT: begin
                sel_rom = 1'b1;
                if (txb_falling) begin // Esperamos a que termine de transmitir
                    update_checksum = 1'b1;
                    if (ptr_reg == 5'd3) begin
                        next_ptr = 5'd0;
                        next_state = TX_RAM_SETUP;
                    end else begin
                        next_ptr = ptr_reg + 1'b1;
                        next_state = TX_ROM_SETUP;
                    end
                end
            end

            TX_RAM_SETUP: begin
                sel_rom = 1'b0;
                load_tx = 1'b1;
                if (txb_active) begin
                    next_state = TX_RAM_WAIT;
                end
            end

            TX_RAM_WAIT: begin
                sel_rom = 1'b0;
                if (txb_falling) begin
                    update_checksum = 1'b1;
                    if (ptr_reg == 5'd21) begin
                        next_state = TX_CHK_SETUP;
                    end else begin
                        next_ptr = ptr_reg + 1'b1;
                        next_state = TX_RAM_SETUP;
                    end
                end
            end

            TX_CHK_SETUP: begin
                send_checksum = 1'b1;
                load_tx = 1'b1;
                if (txb_active) begin
                    next_state = TX_CHK_WAIT;
                end
            end

            TX_CHK_WAIT: begin
                send_checksum = 1'b1;
                if (txb_falling) begin
                    next_state = DONE;
                end
            end

            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule

