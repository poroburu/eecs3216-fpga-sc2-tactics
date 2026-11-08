// Generic v1 envelope serializer. Metadata/payload must stay stable through done.
// Payload interface is combinational (or prefetch in caller); byte interface has backpressure.
module packet_tx (
    input wire clk, rst, start,
    output wire ready,
    input wire [7:0] kind,
    input wire [31:0] round_id, snapshot_id,
    input wire [15:0] payload_length,
    output wire [8:0] payload_address,
    input wire [7:0] payload_data,
    output reg [7:0] byte_data,
    output wire byte_valid,
    input wire byte_ready,
    output reg done
);
    reg busy;
    reg [15:0] offset;
    reg [7:0] checksum;
    assign ready = !busy;
    assign byte_valid = busy;
    assign payload_address = offset >= 14 ? offset[8:0]-9'd14 : 9'd0;
    always @* begin
        case (offset)
            0: byte_data = 8'ha5;
            1: byte_data = 8'h5a;
            2: byte_data = 1;
            3: byte_data = kind;
            4,5,6,7: byte_data = round_id[(offset-4)*8 +: 8];
            8,9,10,11: byte_data = snapshot_id[(offset-8)*8 +: 8];
            12: byte_data = payload_length[7:0];
            13: byte_data = payload_length[15:8];
            default: byte_data = offset == 14+payload_length ? -checksum : payload_data;
        endcase
    end
    always @(posedge clk) begin
        done <= 0;
        if (rst) begin busy <= 0; offset <= 0; checksum <= 0; end
        else if (!busy) begin
            if (start && payload_length <= 462) begin busy <= 1; offset <= 0; checksum <= 0; end
        end else if (byte_ready) begin
            if (offset >= 2) checksum <= checksum+byte_data;
            if (offset == 14+payload_length) begin busy <= 0; done <= 1; end
            else offset <= offset+1'b1;
        end
    end
endmodule
