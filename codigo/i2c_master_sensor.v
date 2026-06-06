// Módulo 2: i2c_master_sensor (Captura de Carga Útil)
// Máquina de estados I2C Master totalmente síncrona (1 solo always block).
// Resuelve el error de Synthesis "Multiple Constant Drivers".

module i2c_master_sensor (
    input wire clk_100k,
    input wire rst_n,
    output reg scl,
    inout wire sda,
    output reg data_ready,
    output reg [23:0] payload_data
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
               RX_BYTE_1  = 5'd12,
               ACK_4      = 5'd13,
               RX_BYTE_2  = 5'd14,
               ACK_5      = 5'd15,
               RX_BYTE_3  = 5'd16,
               NACK       = 5'd17,
               STOP1      = 5'd18,
               STOP2      = 5'd19,
               DONE       = 5'd20;

    reg [4:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] tx_data;
    reg phase; // 0 = preparar dato (SCL=0), 1 = muestrear dato (SCL=1)

    localparam ADDR_W = 8'hA6;
    localparam ADDR_R = 8'hA7;
    localparam REG_DATA = 8'h0D;

    always @(posedge clk_100k or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 3'd7;
            phase <= 1'b0;
            scl <= 1'b1;
            sda_out <= 1'b1;
            sda_en <= 1'b1;
            data_ready <= 1'b0;
            payload_data <= 24'd0;
            tx_data <= 8'd0;
        end else begin
            // Pulso data_ready dura 1 ciclo
            if (data_ready) data_ready <= 1'b0;

            case (state)
                IDLE: begin
                    scl <= 1'b1;
                    sda_out <= 1'b1;
                    sda_en <= 1'b1;
                    state <= START1;
                end

                START1: begin
                    scl <= 1'b1;
                    sda_out <= 1'b0; // SDA baja primero
                    sda_en <= 1'b1;
                    state <= START2;
                end

                START2: begin
                    scl <= 1'b0; // SCL baja después
                    tx_data <= ADDR_W;
                    bit_cnt <= 3'd7;
                    phase <= 1'b0;
                    state <= TX_ADDR_W;
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
                        tx_data <= REG_DATA;
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
                        state <= REP_START1;
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
                    tx_data <= ADDR_R;
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
                        state <= RX_BYTE_1;
                    end
                end

                RX_BYTE_1: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        payload_data[16 + bit_cnt] <= sda;
                        phase <= 1'b0;
                        if (bit_cnt == 0) state <= ACK_4;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                ACK_4: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= 1'b0; // ACK = 0
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        bit_cnt <= 3'd7;
                        state <= RX_BYTE_2;
                    end
                end

                RX_BYTE_2: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        payload_data[8 + bit_cnt] <= sda;
                        phase <= 1'b0;
                        if (bit_cnt == 0) state <= ACK_5;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                ACK_5: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_out <= 1'b0; // ACK = 0
                        sda_en <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        phase <= 1'b0;
                        bit_cnt <= 3'd7;
                        state <= RX_BYTE_3;
                    end
                end

                RX_BYTE_3: begin
                    if (phase == 1'b0) begin
                        scl <= 1'b0;
                        sda_en <= 1'b0;
                        phase <= 1'b1;
                    end else begin
                        scl <= 1'b1;
                        payload_data[bit_cnt] <= sda;
                        phase <= 1'b0;
                        if (bit_cnt == 0) state <= NACK;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                NACK: begin
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
                    state <= DONE;
                end

                DONE: begin
                    scl <= 1'b1;
                    sda_out <= 1'b1; // SDA sube con SCL alto (STOP condition)
                    sda_en <= 1'b1;
                    data_ready <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
