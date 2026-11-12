// Toolchain probe: 115200 8-N-1 UART echo, CLKS_PER_BIT = 50e6/115200 ~= 434
module uart_echo (input logic CLOCK_50, input logic [1:0] KEY, input logic UART_RX,
                  output logic UART_TX, output logic [9:0] LEDR);
  localparam int CPB = 434;
  logic rst_n; assign rst_n = KEY[0];
  logic rx_s1, rx_s2; always_ff @(posedge CLOCK_50) {rx_s2, rx_s1} <= {rx_s1, UART_RX};
  // RX
  typedef enum logic [1:0] {R_IDLE, R_START, R_DATA, R_STOP} rst_t; rst_t rs;
  logic [8:0] rc; logic [2:0] rb; logic [7:0] rsh, rdata; logic rvalid;
  always_ff @(posedge CLOCK_50 or negedge rst_n)
    if (!rst_n) begin rs <= R_IDLE; rvalid <= 0; rc <= 0; rb <= 0; end
    else begin
      rvalid <= 0;
      case (rs)
        R_IDLE:  if (!rx_s2) begin rs <= R_START; rc <= CPB/2; end
        R_START: if (rc == 0) begin rs <= rx_s2 ? R_IDLE : R_DATA; rc <= CPB-1; rb <= 0; end else rc <= rc - 1;
        R_DATA:  if (rc == 0) begin rsh <= {rx_s2, rsh[7:1]}; rc <= CPB-1; if (rb == 7) rs <= R_STOP; rb <= rb + 1; end else rc <= rc - 1;
        R_STOP:  if (rc == 0) begin rs <= R_IDLE; if (rx_s2) begin rdata <= rsh; rvalid <= 1; end end else rc <= rc - 1;
      endcase
    end
  // TX
  logic [9:0] tsh; logic [3:0] tb; logic [8:0] tc; logic busy;
  always_ff @(posedge CLOCK_50 or negedge rst_n)
    if (!rst_n) begin busy <= 0; UART_TX <= 1; tb <= 0; tc <= 0; end
    else if (!busy) begin UART_TX <= 1; if (rvalid) begin tsh <= {1'b1, rdata, 1'b0}; busy <= 1; tb <= 0; tc <= 0; end end
    else if (tc == 0) begin UART_TX <= tsh[0]; tsh <= {1'b1, tsh[9:1]}; tc <= CPB-1; if (tb == 10) busy <= 0; tb <= tb + 1; end
    else tc <= tc - 1;
  always_ff @(posedge CLOCK_50) if (rvalid) LEDR[7:0] <= rdata;
  assign LEDR[9:8] = {busy, rs != R_IDLE};
endmodule
