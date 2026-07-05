// Módulo 3: memory_and_framer (Segmentación y Ensamblaje)
// Decodificador de direcciones (ROM y RAM) y calculador de Checksum.

module memory_and_framer (
    input wire clk,
    input wire rst_n,
    input wire [4:0] addr,
    input wire sel_rom,
    input wire we_ram,
    input wire [191:0] payload_data,
    input wire clear_checksum,
    input wire update_checksum,
    output wire [7:0] data_out,
    output reg [7:0] checksum
);

    // Memoria ROM estática para el encabezado
    wire [7:0] ROM_banco [0:3];
    assign ROM_banco[0] = 8'hAA; // SYNC1
    assign ROM_banco[1] = 8'h55; // SYNC2
    assign ROM_banco[2] = 8'h01; // DEVICE_ID
    assign ROM_banco[3] = 8'h18; // PAYLOAD_LEN (24 bytes de RAM)

    // Memoria RAM estática/segmentada
    // Se mapean los 24 bytes de carga útil (MPU6050:14, BME280:8, BH1750:2)
    reg [7:0] RAM_banco [0:23];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i=0; i<24; i=i+1) begin
                RAM_banco[i] <= 8'h00;
            end
        end else if (we_ram) begin
            for(i=0; i<24; i=i+1) begin
                RAM_banco[i] <= payload_data[(23-i)*8 +: 8];
            end
        end
    end

    // Mux Combinacional para data_out
    assign data_out = sel_rom ? ROM_banco[addr[1:0]] : RAM_banco[addr];

    // Cálculo dinámico del Checksum (XOR de los bytes a medida que se transmiten)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            checksum <= 8'h00;
        end else begin
            if (clear_checksum) begin
                checksum <= 8'h00;
            end else if (update_checksum) begin
                checksum <= checksum ^ data_out;
            end
        end
    end

endmodule
