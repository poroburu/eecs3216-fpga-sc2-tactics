// 115200 baud, 8-N-1 at 50 MHz (434 clocks/bit).
module uart_rx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input wire clk,
    input wire serial_in,
    output reg [7:0] data = 8'd0,
    output reg valid = 1'b0
);
    localparam integer TIMER_WIDTH = $clog2(CLKS_PER_BIT);
    localparam [2:0] IDLE=0, START=1, DATA=2, STOP=3, WAIT_HIGH=4;
    reg rx_meta = 1'b1;
    reg rx_sync = 1'b1;
    reg [2:0] state = IDLE;
    reg [TIMER_WIDTH-1:0] timer = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] shift = 0;

    always @(posedge clk) begin
        rx_meta <= serial_in;
        rx_sync <= rx_meta;
        valid <= 1'b0;
        case (state)
            IDLE: if (!rx_sync) begin
                timer <= CLKS_PER_BIT/2 - 1;
                state <= START;
            end
            START: if (timer != 0) timer <= timer - 1'b1;
            else if (!rx_sync) begin
                timer <= CLKS_PER_BIT - 1;
                bit_index <= 0;
                state <= DATA;
            end else state <= IDLE;
            DATA: if (timer != 0) timer <= timer - 1'b1;
            else begin
                shift[bit_index] <= rx_sync;
                timer <= CLKS_PER_BIT - 1;
                if (bit_index == 7) state <= STOP;
                else bit_index <= bit_index + 1'b1;
            end
            STOP: if (timer != 0) timer <= timer - 1'b1;
            else if (rx_sync) begin
                data <= shift;
                valid <= 1'b1;
                state <= IDLE;
            end else state <= WAIT_HIGH;
            WAIT_HIGH: if (rx_sync) state <= IDLE;
            default: state <= IDLE;
        endcase
    end
endmodule
