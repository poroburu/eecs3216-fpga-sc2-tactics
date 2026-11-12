// UART receiver, 8-N-1, LSB first.
// The asynchronous rx line passes through a 2-flop synchronizer. A falling edge starts a frame;
// the start bit is re-checked at its middle, then each data bit and the stop bit are sampled
// at their middles (every CLKS_PER_BIT clocks). A byte with a bad stop bit is discarded.
module uart_rx #(parameter int CLKS_PER_BIT = 434) (   // 50 MHz / 115200 = 434.03
  input  logic       clk,
  input  logic       rst,
  input  logic       rx,
  output logic [7:0] data,
  output logic       valid            // 1-cycle pulse with a good byte
);
  localparam int CW = $clog2(CLKS_PER_BIT + 1);
  typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
  state_t        state;
  logic          rx_m, rx_s;          // synchronizer
  logic [CW-1:0] cnt;
  logic [2:0]    bitn;
  logic [7:0]    shift;

  always_ff @(posedge clk) begin
    rx_m <= rx;
    rx_s <= rx_m;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE; valid <= 1'b0; cnt <= '0; bitn <= '0; shift <= '0; data <= '0;
    end else begin
      valid <= 1'b0;
      case (state)
        IDLE: if (!rx_s) begin state <= START; cnt <= CW'(CLKS_PER_BIT / 2); end
        START:
          if (cnt == 0) begin
            if (rx_s) state <= IDLE;              // glitch, not a real start bit
            else begin state <= DATA; cnt <= CW'(CLKS_PER_BIT - 1); bitn <= '0; end
          end else cnt <= cnt - 1'b1;
        DATA:
          if (cnt == 0) begin
            shift <= {rx_s, shift[7:1]};
            cnt   <= CW'(CLKS_PER_BIT - 1);
            if (bitn == 3'd7) state <= STOP;
            bitn  <= bitn + 1'b1;
          end else cnt <= cnt - 1'b1;
        STOP:
          if (cnt == 0) begin
            state <= IDLE;
            if (rx_s) begin data <= shift; valid <= 1'b1; end
          end else cnt <= cnt - 1'b1;
      endcase
    end
  end
endmodule
