// Módulo 2: i2c_master_sensor (Captura de Carga Útil)
// Máquina de estados I2C Master totalmente síncrona con flujo tipo Polling.
// Lee secuencialmente MPU6050, BMP280 y un ADC.

module i2c_master_sensor (
    input wire clk_100k,
    input wire rst_n,
    output reg scl,
    inout wire sda,
    output reg data_ready,
    output reg [191:0] payload_data
);

    reg sda_out;
    reg sda_en;
    assign sda = sda_en ? sda_out : 1'bz;

    // Estados
    localparam IDLE       = 5'd0,
               START1     = 5'd1,
               START2     = 5'd2,
               TX_ADDR_W  = 5'd3,
               ACK_1      = 5'd4,
               TX_REG     = 5'd5,
               ACK_2      = 5'd6,
               REP_START1 = 5'd7,
               REP_START2 = 5'd8,
               REP_START3 = 5'd9,
               TX_ADDR_R  = 5'd10,
               ACK_3      = 5'd11,
               RX_BYTE    = 5'd12,
               ACK_M      = 5'd13, // Master ACK
               NACK_M     = 5'd14, // Master NACK
               STOP1      = 5'd15,
               STOP2      = 5'd16,
               NEXT_DEV   = 5'd17,
               DONE       = 5'd18;

    reg [4:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] tx_data;
    reg phase; // 0 = preparar dato (SCL=0), 1 = muestrear dato (SCL=1)
    
    // Variables de control de flujo
    reg [1:0] device_idx;
    reg [4:0] bytes_to_read;
    reg [4:0] byte_idx; // Índice global de byte (0 a 21)
    reg bh1750_init_done; // Bandera de inicialización para BH1750

    // Parámetros de Dispositivos
    // 0: MPU6050
    // 1: BMP280
    // 2: ADC
    reg [7:0] curr_addr_w;
    reg [7:0] curr_addr_r;
    reg [7:0] curr_reg;
    reg [4:0] curr_len;

    always @(*) begin
        case (device_idx)
            2'd0: begin
                curr_addr_w = 8'hD0; // MPU6050
                curr_addr_r = 8'hD1;
                curr_reg    = 8'h3B; // ACCEL_XOUT_H
                curr_len    = 5'd14;
            end
            2'd1: begin
                curr_addr_w = 8'hEC; // BME280 addr 0x76
                curr_addr_r = 8'hED;
                curr_reg    = 8'hF7; // press_msb (F7-FE = 8 bytes: press+temp+hum)
                curr_len    = 5'd8;
            end
            2'd2: begin
                if (!bh1750_init_done) begin
                    curr_addr_w = 8'h46; // BH1750 Write Addr (0x23 << 1)
                    curr_addr_r = 8'h47; // BH1750 Read Addr
                    curr_reg    = 8'h10; // Opcode: Continuous H-Res Mode
                    curr_len    = 5'd0;  // 0 bytes to read = Write-Only Transaction
                end else begin
                    curr_addr_w = 8'h00; // Flag to bypass Write Phase (Read-Only)
                    curr_addr_r = 8'h47;
                    curr_reg    = 8'h00; // No importa
                    curr_len    = 5'd2;  // Leer 2 bytes de Lux
                end
            end
            default: begin
                curr_addr_w = 8'h00;
                curr_addr_r = 8'h00;
                curr_reg    = 8'h00;
                curr_len    = 5'd0;
            end
        endcase
    end

    always @(posedge clk_100k or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 3'd7;
            phase <= 1'b0;
            scl <= 1'b1;
            sda_out <= 1'b1;
            sda_en <= 1'b1;
            data_ready <= 1'b0;
            payload_data <= 192'd0;
            tx_data <= 8'd0;
            device_idx <= 2'd0;
            bytes_to_read <= 5'd0;
            byte_idx <= 5'd0;
            bh1750_init_done <= 1'b0;
        end else begin
            // Pulso data_ready dura 1 ciclo
            if (data_ready) data_ready <= 1'b0;

            case (state)
                IDLE: begin
                    scl <= 1'b1;
                    sda_out <= 1'b1;
                    sda_en <= 1'b1;
                    device_idx <= 2'd0;
                    byte_idx <= 5'd0;
                    state <= START1;
                end

                START1: begin
                    scl <= 1'b1;
                    sda_out <= 1'b0; // SDA baja primero
                    sda_en <= 1'b1;
                    bytes_to_read <= curr_len;
                    state <= START2;
                end

                START2: begin
                    scl <= 1'b0; // SCL baja después
                    if (curr_addr_w == 8'h00) begin
                        // Skip Write Phase -> Go directly to Read Phase
                        tx_data <= curr_addr_r;
                        bit_cnt <= 3'd7;
                        phase <= 1'b0;
                        state <= TX_ADDR_R;
                    end else begin
                        tx_data <= curr_addr_w;
                        bit_cnt <= 3'd7;
                        phase <= 1'b0;
                        state <= TX_ADDR_W;
                    end
                end

                TX_ADDR_W: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= tx_data[bit_cnt];
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1; // Subir SCL
                        phase <= 1'b0;
                        if (bit_cnt == 0) state <= ACK_1;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                ACK_1: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0; // Libera bus para ACK
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        tx_data <= curr_reg;
                        bit_cnt <= 3'd7;
                        state <= TX_REG;
                    end
                end

                TX_REG: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= tx_data[bit_cnt];
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        if (bit_cnt == 0) state <= ACK_2;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                ACK_2: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        if (curr_len == 5'd0) begin
                            // Transacción de Solo Escritura Finalizada
                            if (device_idx == 2'd2) bh1750_init_done <= 1'b1;
                            state <= STOP1;
                        end else begin
                            state <= REP_START1;
                        end
                    end
                end

                REP_START1: begin
                    scl <= 1'b0;
                    sda_out <= 1'b1; // Preparar SDA alta
                    sda_en <= 1'b1;
                    state <= REP_START2;
                end

                REP_START2: begin
                    scl <= 1'b1; // SCL sube
                    state <= REP_START3;
                end

                REP_START3: begin
                    scl <= 1'b1;
                    sda_out <= 1'b0; // SDA baja con SCL alto (Repeated Start)
                    tx_data <= curr_addr_r;
                    bit_cnt <= 3'd7;
                    phase <= 1'b0;
                    state <= TX_ADDR_R;
                end

                TX_ADDR_R: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= tx_data[bit_cnt];
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        if (bit_cnt == 0) state <= ACK_3;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                ACK_3: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        bit_cnt <= 3'd7;
                        state <= RX_BYTE;
                    end
                end

                RX_BYTE: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        payload_data[ ((5'd23 - byte_idx) * 8) + bit_cnt ] <= sda;
                        phase <= 1'b0;
                        if (bit_cnt == 0) begin
                            bytes_to_read <= bytes_to_read - 1'b1;
                            byte_idx <= byte_idx + 1'b1;
                            if (bytes_to_read == 5'd1) state <= NACK_M; // Último byte -> NACK
                            else state <= ACK_M; // Faltan bytes -> ACK
                        end
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                ACK_M: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= 1'b0; // ACK = 0
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        bit_cnt <= 3'd7;
                        state <= RX_BYTE;
                    end
                end

                NACK_M: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= 1'b1; // NACK = 1
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        state <= STOP1;
                    end
                end

                STOP1: begin
                    scl <= 1'b0;
                    sda_out <= 1'b0; // Preparar SDA bajo
                    sda_en <= 1'b1;
                    state <= STOP2;
                end

                STOP2: begin
                    scl <= 1'b1; // SCL sube
                    state <= NEXT_DEV;
                end

                NEXT_DEV: begin
                    scl <= 1'b1;
                    sda_out <= 1'b1; // SDA sube con SCL alto (STOP condition)
                    sda_en <= 1'b1;
                    
                    if (device_idx == 2'd2) begin
                        data_ready <= 1'b1;
                        state <= IDLE;
                    end else begin
                        device_idx <= device_idx + 1'b1;
                        state <= START1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
