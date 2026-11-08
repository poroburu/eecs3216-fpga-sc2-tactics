// Schematic VGA view of the last computed snapshot (the FPGA's own view, not SC2 video).
//
//   rows 0..23 : banner. Orange = FOCUS policy, cyan = CLOSEST, red = last frame was an error.
//   map area   : 1 map unit = 32 pixels (one Q.4 coordinate step = 2 pixels), dim grid every map unit.
//                map_x = 368 + px/2, map_y = 568 - py/2 in Q.4 (SC2 y grows upward). The view is
//                centred on the DefeatRoaches arena: map x 23..43, y 20.5..35.5.
//   enemy j    : hollow square (15x15 Q.4 = 30 px) in palette[j]; a filled centre if any friendly targets it.
//   friendly i : solid square (7x7 Q.4 = 14 px) in the colour of its target (palette[target]); grey if none.
//   line i->j  : half-brightness palette[target] line from each friendly to its target.
// Matching colours and the lines show which friendly unit shoots which enemy.
//
// Four pipeline stages (A hit tests, B multiply, C line compare, D colour) = 4 clocks;
// syncs are delayed to match. 32 signed 13x13 multipliers draw the 16 lines.
import sc2fpga_pkg::*;
module vga_render (
  input  logic          clk,
  input  logic [9:0]    x, y,
  input  logic          visible, hsync_n_in, vsync_n_in,
  input  logic [4:0]    n_f, n_e,
  input  logic [CW-1:0] f_x [MAX_UNITS], f_y [MAX_UNITS], e_x [MAX_UNITS], e_y [MAX_UNITS],
  input  logic [7:0]    target [MAX_UNITS],
  input  logic          policy, error,
  output logic [3:0]    r, g, b,
  output logic          hsync_n, vsync_n
);

  function automatic logic [11:0] pal(input logic [2:0] j);   // {r,g,b} 4 bits each
    case (j)
      3'd0: pal = 12'hF22; 3'd1: pal = 12'hFF2; 3'd2: pal = 12'hF2F; 3'd3: pal = 12'hF82;
      3'd4: pal = 12'h2FF; 3'd5: pal = 12'h8F2; 3'd6: pal = 12'hA6F; default: pal = 12'hFFF;
    endcase
  endfunction

  // pixel -> map coordinates (signed 12 bit)
  logic signed [12:0] mx, my;
  assign mx = 13'sd368 + $signed({4'b0, x[9:1]});
  assign my = 13'sd568 - $signed({4'b0, y[9:1]});

  // ---------- per-line constants (one line per friendly unit, to its target) ----------
  // Inputs only change when a new result is latched, so these registers are effectively static.
  logic signed [12:0] l_dx [MAX_UNITS], l_dy [MAX_UNITS];     // target - friendly (Q.4)
  logic        [11:0] l_len [MAX_UNITS];                      // max(|dx|,|dy|): line length estimate
  logic signed [12:0] l_x0 [MAX_UNITS], l_x1 [MAX_UNITS], l_y0 [MAX_UNITS], l_y1 [MAX_UNITS]; // bounding box
  logic [MAX_UNITS-1:0] l_on;                                 // this friendly has a valid target
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic signed [12:0] fx, fy, ex, ey, dx, dy;
      fx = $signed({2'b0, f_x[k]}); fy = $signed({2'b0, f_y[k]});
      ex = $signed({2'b0, e_x[target[k][3:0]]}); ey = $signed({2'b0, e_y[target[k][3:0]]});
      dx = ex - fx; dy = ey - fy;
      l_dx[k] <= dx; l_dy[k] <= dy;
      l_len[k] <= ((dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy)) ? 12'(dx < 0 ? -dx : dx) : 12'(dy < 0 ? -dy : dy);
      l_x0[k] <= (fx < ex ? fx : ex) - 13'sd1; l_x1[k] <= (fx < ex ? ex : fx) + 13'sd1;
      l_y0[k] <= (fy < ey ? fy : ey) - 13'sd1; l_y1[k] <= (fy < ey ? ey : fy) + 13'sd1;
      l_on[k] <= (k < n_f) && (target[k] != NO_TARGET) && ({1'b0, target[k][3:0]} < n_e);
    end
  end

  // ---------- stage A: marker hit tests, line offsets and bounding box ----------
  logic [MAX_UNITS-1:0] fhit, ering, ecore, targeted, l_box;
  logic signed [12:0] l_rx [MAX_UNITS], l_ry [MAX_UNITS];     // pixel - friendly (Q.4)
  logic a_vis, a_hs, a_vs, a_banner, a_grid;
  always_comb begin
    targeted = '0;
    for (int k = 0; k < MAX_UNITS; k++)
      if (k < n_f && target[k] != NO_TARGET) targeted[target[k][3:0]] = 1'b1;
  end
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic signed [12:0] dfx, dfy, dex, dey;
      dfx = mx - $signed({2'b0, f_x[k]});  dfy = my - $signed({2'b0, f_y[k]});
      dex = mx - $signed({2'b0, e_x[k]});  dey = my - $signed({2'b0, e_y[k]});
      fhit[k]  <= (k < n_f) && dfx >= -3 && dfx <= 3 && dfy >= -3 && dfy <= 3;
      ering[k] <= (k < n_e) && dex >= -7 && dex <= 7 && dey >= -7 && dey <= 7 &&
                  !(dex >= -5 && dex <= 5 && dey >= -5 && dey <= 5);
      ecore[k] <= (k < n_e) && targeted[k] && dex >= -2 && dex <= 2 && dey >= -2 && dey <= 2;
      l_rx[k]  <= dfx; l_ry[k] <= dfy;
      l_box[k] <= l_on[k] && mx >= l_x0[k] && mx <= l_x1[k] && my >= l_y0[k] && my <= l_y1[k];
    end
    a_vis <= visible; a_hs <= hsync_n_in; a_vs <= vsync_n_in;
    a_banner <= (y < 10'd24);
    a_grid   <= (mx[3:0] == 4'd0 && !x[0]) || (my[3:0] == 4'd0 && !y[0]);
  end

  // ---------- stage B: cross-product terms (2 multipliers per line) ----------
  // cross = rx*dy - ry*dx is |P-F| * |T-F| * sin(angle): zero on the line through F and T.
  logic signed [25:0] l_p1 [MAX_UNITS], l_p2 [MAX_UNITS];
  logic [MAX_UNITS-1:0] b_fhit, b_ering, b_ecore, b_box;
  logic b_vis, b_hs, b_vs, b_banner, b_grid;
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      l_p1[k] <= l_rx[k] * l_dy[k];
      l_p2[k] <= l_ry[k] * l_dx[k];
    end
    b_fhit <= fhit; b_ering <= ering; b_ecore <= ecore; b_box <= l_box;
    b_vis <= a_vis; b_hs <= a_hs; b_vs <= a_vs; b_banner <= a_banner; b_grid <= a_grid;
  end

  // ---------- stage C: line hit = inside the box and |cross| <= length ----------
  // |cross| / |T-F| is the pixel's distance from the line; comparing against max(|dx|,|dy|)
  // keeps it within about 1 Q.4 unit (2 pixels) without a divider or square root.
  logic [MAX_UNITS-1:0] lhit, c_fhit, c_ering, c_ecore;
  logic c_vis, c_hs, c_vs, c_banner, c_grid;
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic signed [26:0] cr;
      cr = 27'(l_p1[k]) - 27'(l_p2[k]);
      lhit[k] <= b_box[k] && ((cr < 0 ? -cr : cr) <= $signed({15'd0, l_len[k]}));
    end
    c_fhit <= b_fhit; c_ering <= b_ering; c_ecore <= b_ecore;
    c_vis <= b_vis; c_hs <= b_hs; c_vs <= b_vs; c_banner <= b_banner; c_grid <= b_grid;
  end

  // ---------- stage D: colour select (markers over lines over grid; lowest index wins) ----------
  always_ff @(posedge clk) begin
    logic [11:0] c, lc;
    c = c_grid ? 12'h222 : 12'h000;
    for (int k = MAX_UNITS - 1; k >= 0; k--)
      if (lhit[k]) begin lc = pal(target[k][2:0]); c = {1'b0, lc[11:9], 1'b0, lc[7:5], 1'b0, lc[3:1]}; end  // half brightness
    for (int k = MAX_UNITS - 1; k >= 0; k--) if (c_ering[k] || c_ecore[k]) c = pal(k[2:0]);
    for (int k = MAX_UNITS - 1; k >= 0; k--)
      if (c_fhit[k]) c = (target[k] == NO_TARGET) ? 12'h888 : pal(target[k][2:0]);
    if (c_banner) c = error ? 12'hF00 : (policy ? 12'hF80 : 12'h0CC);
    if (!c_vis) c = 12'h000;
    {r, g, b} <= c;
    hsync_n <= c_hs; vsync_n <= c_vs;
  end
endmodule
