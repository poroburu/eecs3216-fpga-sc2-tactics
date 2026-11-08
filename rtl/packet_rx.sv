// Request parser and semantic validation for docs/protocol.md.
// Two byte banks: only a fully validated frame can replace active memory.
// Consumer owns session IDs/cache and computation; hold packet_ready low while busy.
module packet_rx #(
    parameter integer MAX_PAYLOAD = 462,
    parameter integer TIMEOUT_TICKS = 5_000_000
) (
    input wire clk, rst,
    input wire [7:0] byte_data,
    input wire byte_valid, framing_error,
    output reg packet_valid,
    input wire packet_ready,
    output reg [7:0] packet_kind,
    output reg [31:0] round_id, snapshot_id,
    output reg [15:0] payload_length,
    input wire [8:0] read_address,
    output reg [7:0] read_data,
    output reg [31:0] rejected, timeouts, overruns
);
    localparam HUNT=0, SYNC2=1, HEADER=2, PAYLOAD=3, CHECK=4;
    reg [2:0] state;
    reg [7:0] memory [0:2*MAX_PAYLOAD-1];
    reg active_bank;
    reg [3:0] header_index;
    reg [15:0] length, position;
    reg [7:0] checksum, kind;
    reg [31:0] candidate_round, candidate_snapshot;
    reg bad;
    integer gap;
    reg [7:0] nf, ne, previous_index;
    reg [31:0] initial_health, current_max_sum;
    reg [15:0] health;
    reg [7:0] low_byte;
    reg [5:0] record_number;
    reg [3:0] field_offset;
    always @(posedge clk) begin
        if (read_address < MAX_PAYLOAD)
            read_data <= memory[(active_bank ? MAX_PAYLOAD : 0) + read_address];
        else read_data <= 0;
        if (rst) begin
            state <= HUNT; active_bank <= 0; packet_valid <= 0;
            packet_kind <= 0; round_id <= 0; snapshot_id <= 0; payload_length <= 0;
            rejected <= 0; timeouts <= 0; overruns <= 0; gap <= 0;
            header_index <= 0; length <= 0; position <= 0; checksum <= 0;
            candidate_round <= 0; candidate_snapshot <= 0; kind <= 0; bad <= 0;
            nf <= 0; ne <= 0; previous_index <= 0; initial_health <= 0;
            current_max_sum <= 0; health <= 0; low_byte <= 0;
            record_number <= 0; field_offset <= 0;
        end else begin
            if (packet_valid && packet_ready) packet_valid <= 0;
            if (state != HUNT) gap <= gap+1;
            if (framing_error || (state != HUNT && gap >= TIMEOUT_TICKS-1)) begin
                state <= HUNT; gap <= 0;
                if (framing_error) rejected <= rejected+1;
                else timeouts <= timeouts+1;
                // A byte on the timeout boundary is the start of a new hunt.
                if (byte_valid && !framing_error && byte_data == 8'ha5) state <= SYNC2;
            end else if (byte_valid) begin
                gap <= 0;
                if (packet_valid) begin
                    overruns <= overruns+1; state <= HUNT;
                end else case (state)
                    HUNT: if (byte_data == 8'ha5) state <= SYNC2;
                    SYNC2: if (byte_data == 8'h5a) begin
                        state <= HEADER; header_index <= 0; checksum <= 0;
                        bad <= 0; initial_health <= 0; current_max_sum <= 0;
                        record_number <= 0; field_offset <= 0;
                    end else if (byte_data != 8'ha5) state <= HUNT;
                    HEADER: begin
                        checksum <= checksum+byte_data;
                        header_index <= header_index+1'b1;
                        case (header_index)
                            0: if (byte_data != 1) bad <= 1;
                            1: begin
                                kind <= byte_data;
                                if (byte_data != 1 && byte_data != 2) bad <= 1;
                            end
                            2,3,4,5: candidate_round[(header_index-2)*8 +: 8] <= byte_data;
                            6,7,8,9: candidate_snapshot[(header_index-6)*8 +: 8] <= byte_data;
                            10: length[7:0] <= byte_data;
                            11: begin
                                length[15:8] <= byte_data;
                                position <= 0;
                                if (bad || {byte_data, length[7:0]} > MAX_PAYLOAD) begin
                                    rejected <= rejected+1; state <= HUNT;
                                end else if ({byte_data, length[7:0]} == 0) state <= CHECK;
                                else state <= PAYLOAD;
                            end
                        endcase
                    end
                    PAYLOAD: begin
                        memory[(active_bank ? 0 : MAX_PAYLOAD)+position] <= byte_data;
                        checksum <= checksum+byte_data;
                        position <= position+1'b1;
                        if (position == length-1) state <= CHECK;
                        case (position)
                            0: begin nf <= byte_data; if (byte_data > 16) bad <= 1; end
                            1: begin ne <= byte_data; if (byte_data > 16) bad <= 1; end
                            2,3,4,5: initial_health[(position-2)*8 +: 8] <= byte_data;
                            default: begin end
                        endcase
                        if (position >= 14) begin
                          if (field_offset == 13) begin
                              field_offset <= 0; record_number <= record_number+1'b1;
                          end else field_offset <= field_offset+1'b1;
                          case (field_offset)
                            0: begin
                                if (byte_data > 15 ||
                                    (record_number != 0 && record_number != nf && byte_data <= previous_index)) bad <= 1;
                                previous_index <= byte_data;
                            end
                            1: if (byte_data > 1 || (record_number >= nf && byte_data != 0)) bad <= 1;
                            6,8,10: low_byte <= byte_data;
                            7: begin
                                health <= {byte_data, low_byte};
                                if ({byte_data, low_byte} == 0) bad <= 1;
                            end
                            9: begin
                                if ({byte_data, low_byte} < health) bad <= 1;
                                if (record_number < nf) current_max_sum <= current_max_sum+{byte_data, low_byte};
                            end
                            11: if ({byte_data, low_byte} == 0) bad <= 1;
                            default: begin end
                          endcase
                        end
                    end
                    CHECK: begin
                        state <= HUNT;
                        if ((checksum+byte_data) % 256 != 0 || bad || candidate_round == 0 ||
                            (kind == 1 && (length != 0 || candidate_snapshot != 0)) ||
                            (kind == 2 && (candidate_snapshot == 0 || length != 14+14*(nf+ne) ||
                              initial_health > 1048560 || initial_health < current_max_sum)))
                            rejected <= rejected+1;
                        else begin
                            packet_valid <= 1; active_bank <= !active_bank;
                            packet_kind <= kind; round_id <= candidate_round;
                            snapshot_id <= candidate_snapshot; payload_length <= length;
                        end
                    end
                    default: state <= HUNT;
                endcase
            end
        end
    end
endmodule
