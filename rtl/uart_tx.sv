// UART transmitter, 8-N-1, LSB first. Assert `start` for one cycle while `busy` is low.
module uart_tx #(parameter int CLKS_PER_BIT = 434) (
  input  logic       clk,
  input  logic       rst,
  input  logic       start,
  input  logic [7:0] data,
  output logic       tx,
  output logic       busy
);
  localparam int CW = $clog2(CLKS_PER_BIT + 1);
  logic [CW-1:0] cnt;
  logic [3:0]    bitn;     // 0 = start bit, 1..8 = data, 9 = stop bit
  logic [9:0]    frame;    // {stop, data[7:0], start}

  always_ff @(posedge clk) begin
    if (rst) begin
      tx <= 1'b1; busy <= 1'b0; cnt <= '0; bitn <= '0; frame <= '1;
    end else if (!busy) begin
      tx <= 1'b1;
      if (start) begin
        frame <= {1'b1, data, 1'b0};
        busy  <= 1'b1; bitn <= '0; cnt <= '0;
      end
    end else if (cnt == 0) begin
      if (bitn == 4'd10) busy <= 1'b0;       // stop bit has been on the line for a full bit time
      else begin
        tx    <= frame[0];
        frame <= {1'b1, frame[9:1]};
        cnt   <= CW'(CLKS_PER_BIT - 1);
        bitn  <= bitn + 1'b1;
      end
    end else cnt <= cnt - 1'b1;
  end
endmodule
