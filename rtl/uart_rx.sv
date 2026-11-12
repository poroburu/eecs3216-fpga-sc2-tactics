// 8N1 receiver. Synchronous active-high reset; 2-FF asynchronous input synchronizer.
module uart_rx #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer BIT_TICKS = (CLOCK_HZ + BAUD/2) / BAUD
) (
    input wire clk, rst, rx,
    output reg [7:0] data,
    output reg valid, framing_error
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg rx_meta, rx_sync;
    localparam IDLE=0, START=1, DATA=2, STOP=3, BREAK_WAIT=4;
    reg [2:0] state;
    integer ticks;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk) begin
        if (rst) begin rx_meta <= 1; rx_sync <= 1; end
        else begin rx_meta <= rx; rx_sync <= rx_meta; end
    end
    always @(posedge clk) begin
        valid <= 0;
        framing_error <= 0;
        if (rst) begin
            state <= IDLE; ticks <= 0; bit_index <= 0; data <= 0; shift <= 0;
        end else case (state)
            IDLE: if (!rx_sync) begin state <= START; ticks <= BIT_TICKS/2-1; end
            START: if (ticks != 0) ticks <= ticks-1;
                   else if (rx_sync) state <= IDLE;
                   else begin state <= DATA; ticks <= BIT_TICKS-1; bit_index <= 0; end
            DATA: if (ticks != 0) ticks <= ticks-1;
                  else begin
                      shift[bit_index] <= rx_sync;
                      ticks <= BIT_TICKS-1;
                      if (bit_index == 7) state <= STOP;
                      else bit_index <= bit_index+1'b1;
                  end
            STOP: if (ticks != 0) ticks <= ticks-1;
                  else if (rx_sync) begin data <= shift; valid <= 1; state <= IDLE; end
                  else begin framing_error <= 1; state <= BREAK_WAIT; end
            BREAK_WAIT: if (rx_sync) state <= IDLE;
            default: state <= IDLE;
        endcase
    end
endmodule
