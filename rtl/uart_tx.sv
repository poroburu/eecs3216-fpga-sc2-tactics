// Ready/valid byte input, one start + eight LSB-first data + one stop bit.
module uart_tx #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer BIT_TICKS = (CLOCK_HZ + BAUD/2) / BAUD
) (
    input wire clk, rst,
    input wire [7:0] data,
    input wire valid,
    output wire ready,
    output wire tx
);
    reg [9:0] shift;
    reg [3:0] remaining;
    integer ticks;
    assign ready = remaining == 0;
    assign tx = remaining == 0 ? 1'b1 : shift[0];
    always @(posedge clk) begin
        if (rst) begin shift <= 10'h3ff; remaining <= 0; ticks <= 0; end
        else if (remaining == 0) begin
            if (valid) begin shift <= {1'b1, data, 1'b0}; remaining <= 10; ticks <= BIT_TICKS-1; end
        end else if (ticks == 0) begin
            shift <= {1'b1, shift[9:1]}; remaining <= remaining-1'b1; ticks <= BIT_TICKS-1;
        end else ticks <= ticks-1;
    end
endmodule
