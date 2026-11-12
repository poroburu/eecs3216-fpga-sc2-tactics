// Diagnostic endpoint only: START ACK, SNAPSHOT -> UNSUPPORTED.
// No tactical decisions; intentionally fails host.decide rather than pretending HOLD.
module uart_diagnostic(input wire clk_50, uart_rx, output wire uart_tx);
    reg [7:0] power_on = 0;
    wire rst = !(&power_on);
    always @(posedge clk_50) if (rst) power_on <= power_on+1'b1;
    wire [7:0] rx_byte;
    wire rx_valid, rx_error;
    uart_rx receiver(.clk(clk_50),.rst(rst),.rx(uart_rx),.data(rx_byte),.valid(rx_valid),.framing_error(rx_error));
    wire packet_valid;
    wire [7:0] packet_kind;
    wire [31:0] round_id, snapshot_id;
    wire [15:0] payload_length;
    wire [7:0] read_data;
    wire [31:0] rejected, timeouts, overruns;
    reg [1:0] state=0;
    packet_rx packets(.clk(clk_50),.rst(rst),.byte_data(rx_byte),.byte_valid(rx_valid),
        .framing_error(rx_error),.packet_valid(packet_valid),.packet_ready(state==2),
        .packet_kind(packet_kind),.round_id(round_id),.snapshot_id(snapshot_id),
        .payload_length(payload_length),.read_address(9'd0),.read_data(read_data),
        .rejected(rejected),.timeouts(timeouts),.overruns(overruns));
    reg start=0;
    wire frame_ready, frame_done;
    wire [8:0] payload_address;
    wire [7:0] tx_byte;
    wire tx_valid, tx_ready;
    wire [7:0] status_byte = packet_kind == 1 ? 8'd0 : 8'd6;
    packet_tx replies(.clk(clk_50),.rst(rst),.start(start),.ready(frame_ready),
        .kind(8'h81),.round_id(round_id),.snapshot_id(snapshot_id),.payload_length(16'd8),
        .payload_address(payload_address),.payload_data(payload_address==0 ? status_byte : 8'd0),
        .byte_data(tx_byte),.byte_valid(tx_valid),.byte_ready(tx_ready),.done(frame_done));
    uart_tx transmitter(.clk(clk_50),.rst(rst),.data(tx_byte),.valid(tx_valid),.ready(tx_ready),.tx(uart_tx));
    always @(posedge clk_50) begin
        start <= 0;
        if (rst) state <= 0;
        else case (state)
            0: if (packet_valid && frame_ready) begin start <= 1; state <= 1; end
            1: if (frame_done) state <= 2;
            2: state <= 0;
            default: state <= 0;
        endcase
    end
endmodule
