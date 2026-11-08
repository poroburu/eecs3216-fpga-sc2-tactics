// Renders one VGA frame to a PPM image: sends one request through the UART (as tb_sc2fpga does),
// waits for the reply, then records 640x480 pixels exactly as they appear on VGA_R/G/B.
// usage: tb +VEC=<one-case .mem> +OUT=<file.ppm>
`timescale 1ns/1ps
module tb_vga_frame;
  localparam int CPB = 8;
  logic clk = 0; always #10 clk = ~clk;
  logic [1:0] key = 2'b11; logic [9:0] sw = '0; logic rx_line = 1'b1;
  wire [35:0] gpio; assign gpio[0] = rx_line;
  logic [9:0] ledr; logic [7:0] h0, h1, h2, h3, h4, h5; logic [3:0] vr, vg, vb; logic hs, vs;
  sc2fpga_top #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(3000)) dut (
    .MAX10_CLK1_50(clk), .KEY(key), .SW(sw), .LEDR(ledr), .HEX0(h0), .HEX1(h1), .HEX2(h2), .HEX3(h3),
    .HEX4(h4), .HEX5(h5), .VGA_R(vr), .VGA_G(vg), .VGA_B(vb), .VGA_HS(hs), .VGA_VS(vs), .GPIO(gpio));

  logic [11:0] vec [0:4095];
  logic [11:0] img [0:479][0:639];
  string VEC = "frame.mem", OUT = "frame.ppm";
  // colour on the pins at clock t belongs to the pixel counters of clock t-LAT (renderer latency)
  localparam int LAT = 4;
  logic [9:0] xd [LAT], yd [LAT]; logic vd [LAT];
  always_ff @(posedge clk) begin
    xd[0] <= dut.vx; yd[0] <= dut.vy; vd[0] <= dut.vis;
    for (int i = 1; i < LAT; i++) begin xd[i] <= xd[i-1]; yd[i] <= yd[i-1]; vd[i] <= vd[i-1]; end
  end
  wire [9:0] x2 = xd[LAT-1], y2 = yd[LAT-1]; wire v2 = vd[LAT-1];

  task automatic send_byte(input byte unsigned b);
    rx_line = 0; repeat (CPB) @(posedge clk);
    for (int i = 0; i < 8; i++) begin rx_line = b[i]; repeat (CPB) @(posedge clk); end
    rx_line = 1; repeat (CPB) @(posedge clk);
  endtask

  initial begin
    int f;
    void'($value$plusargs("VEC=%s", VEC)); void'($value$plusargs("OUT=%s", OUT));
    $readmemh(VEC, vec);
    key[0] = 0; repeat (20) @(posedge clk); key[0] = 1; repeat (20) @(posedge clk);
    for (int a = 0; vec[a][11:8] != 4'h3; a++) begin
      if (vec[a][11:8] == 4'h4) begin sw[0] = vec[a][0]; repeat (8) @(posedge clk); end
      if (vec[a][11:8] == 4'h1) send_byte(vec[a][7:0]);
    end
    wait (dut.ctrl == dut.C_REPLY); wait (dut.ctrl == dut.C_IDLE);
    // wait for the start of a fresh frame, then capture it
    wait (dut.vy == 10'd500); wait (dut.vy == 10'd0 && dut.vx == 10'd0);
    repeat (4) @(posedge clk);
    while (!(y2 == 10'd479 && x2 == 10'd639)) begin
      @(posedge clk);
      if (v2) img[y2][x2] = {vr, vg, vb};
    end
    f = $fopen(OUT, "w");
    $fwrite(f, "P3\n640 480\n15\n");
    for (int y = 0; y < 480; y++) for (int x = 0; x < 640; x++)
      $fwrite(f, "%0d %0d %0d\n", img[y][x][11:8], img[y][x][7:4], img[y][x][3:0]);
    $fclose(f);
    $display("wrote %s (HEX0..5 segments %02x %02x %02x %02x %02x %02x, LEDR %b)", OUT, h0, h1, h2, h3, h4, h5, ledr);
    $finish;
  end
endmodule
