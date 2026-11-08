// 640x480 @ 60 Hz VGA timing. A pixel advances on every `pix_en` (25 MHz from the 50 MHz clock).
// Horizontal: 640 visible, 16 front porch, 96 sync, 48 back porch = 800.
// Vertical:   480 visible, 10 front porch,  2 sync, 33 back porch = 525.  Both syncs active-low.
module vga_timing (
  input  logic       clk,
  input  logic       rst,
  input  logic       pix_en,
  output logic [9:0] x, y,
  output logic       visible, hsync_n, vsync_n
);
  always_ff @(posedge clk) begin
    if (rst) begin x <= 0; y <= 0; end
    else if (pix_en) begin
      if (x == 10'd799) begin
        x <= 0;
        y <= (y == 10'd524) ? 10'd0 : y + 1'b1;
      end else x <= x + 1'b1;
    end
  end
  assign visible = (x < 10'd640) && (y < 10'd480);
  assign hsync_n = !((x >= 10'd656) && (x < 10'd752));
  assign vsync_n = !((y >= 10'd490) && (y < 10'd492));
endmodule
