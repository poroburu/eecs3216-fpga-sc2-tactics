// System-level testbench: drives the real top level through its UART pins, exactly as the PC does.
//
// For every case in the vector file it sets SW0, serially transmits the request bytes on GPIO[0],
// captures the reply bytes from GPIO[1], and compares them byte-for-byte with the reply that the
// independent Python reference (host/sc2fpga/reference.py) says is correct. Targets, status,
// policy echo, the cycle count, and the checksum are all checked.
//
// Select the vector file with +VEC=<file.mem> (default directed.mem).
// Vector words (12-bit hex): 4pp set SW0 | 1bb request byte | 2bb expected byte | 300 run | FFF end
`timescale 1ns/1ps
module tb_sc2fpga;
  localparam int CPB = 8;            // fast UART for simulation (8 clocks per bit)
  localparam int TIMEOUT = 3000;     // parser inter-byte timeout in clocks (> 1 byte time)
  string VEC = "directed.mem";

  logic clk = 0; always #10 clk = ~clk;   // 50 MHz
  logic [1:0] key = 2'b11;
  logic [9:0] sw = '0;
  logic rx_line = 1'b1;
  wire  [35:0] gpio;
  assign gpio[0] = rx_line;
  logic [9:0] ledr; logic [7:0] h0, h1, h2, h3, h4, h5; logic [3:0] vr, vg, vb; logic hs, vs;

  sc2fpga_top #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(TIMEOUT)) dut (
    .MAX10_CLK1_50(clk), .KEY(key), .SW(sw), .LEDR(ledr),
    .HEX0(h0), .HEX1(h1), .HEX2(h2), .HEX3(h3), .HEX4(h4), .HEX5(h5),
    .VGA_R(vr), .VGA_G(vg), .VGA_B(vb), .VGA_HS(hs), .VGA_VS(vs), .GPIO(gpio));

  logic [11:0] vec [0:(1<<21)-1];
  byte unsigned req[$], exp_q[$], got[$];
  int pass = 0, fail = 0, ncase = 0;
  int vec_file;

  task automatic send_byte(input byte unsigned b);
    rx_line = 0; repeat (CPB) @(posedge clk);
    for (int i = 0; i < 8; i++) begin rx_line = b[i]; repeat (CPB) @(posedge clk); end
    rx_line = 1; repeat (CPB) @(posedge clk);
  endtask

  task automatic recv_byte(output byte unsigned b, output bit ok);
    int waited = 0;
    ok = 0;
    while (gpio[1] !== 1'b0) begin
      @(posedge clk);
      waited++;
      if (waited > 20 * TIMEOUT) return;
    end
    repeat (CPB / 2) @(posedge clk);
    for (int i = 0; i < 8; i++) begin repeat (CPB) @(posedge clk); b[i] = gpio[1]; end
    repeat (CPB) @(posedge clk);
    ok = (gpio[1] === 1'b1);       // stop bit
  endtask

  task automatic run_case();
    int n = exp_q.size();
    got.delete();
    fork
      foreach (req[i]) send_byte(req[i]);
      begin
        for (int i = 0; i < n; i++) begin
          byte unsigned b; bit ok;
          recv_byte(b, ok);
          if (!ok) break;
          got.push_back(b);
        end
      end
    join
    ncase++;
    if (got == exp_q) pass++;
    else begin
      fail++;
      if (fail <= 10) begin
        $write("FAIL case %0d (SW0=%0d)\n  expected:", ncase, sw[0]); foreach (exp_q[i]) $write(" %02x", exp_q[i]);
        $write("\n  got:     "); foreach (got[i]) $write(" %02x", got[i]); $write("\n");
      end
    end
    repeat (4 * CPB * 10) @(posedge clk);  // idle gap between frames
  endtask

  // passive VGA check: frame period must be 800 x 525 pixels x 2 clocks
  longint t_vs[$];
  always @(negedge vs) t_vs.push_back($time);

  initial begin
    void'($value$plusargs("VEC=%s", VEC));
    vec_file = $fopen(VEC, "r");
    if (vec_file == 0) $fatal(1, "Cannot open vector file %s", VEC);
    $fclose(vec_file);
    $readmemh(VEC, vec);
    key[0] = 0; repeat (20) @(posedge clk); key[0] = 1; repeat (20) @(posedge clk);
    for (int a = 0; vec[a] !== 12'hFFF && vec[a] !== 12'hxxx; a++) begin
      case (vec[a][11:8])
        4'h4: begin sw[0] = vec[a][0]; repeat (8) @(posedge clk); end
        4'h1: req.push_back(vec[a][7:0]);
        4'h2: exp_q.push_back(vec[a][7:0]);
        4'h3: begin run_case(); req.delete(); exp_q.delete(); end
      endcase
    end
    $display("RESULT %s: %0d cases, %0d pass, %0d fail", VEC, ncase, pass, fail);
    if (t_vs.size() >= 2) $display("VGA frame period %0d ns (expected %0d)", t_vs[1] - t_vs[0], 800 * 525 * 2 * 20);
    else $display("VGA frame period: fewer than 2 vsync pulses in this run");
    if (ncase == 0 || fail != 0)
      $fatal(1, "Simulation failed: %0d cases, %0d mismatches", ncase, fail);
    $finish;
  end
endmodule
