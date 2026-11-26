// Schematic VGA view of the last computed snapshot + Lanchester strength bars and squad states.
//
//   rows 0..23    : Policy/error banner (orange=FOCUS, cyan=CLOSEST, red=error) with swatches:
//                   KEY unit (green=Marines, red=Roaches), threshold mode (grey=tuned, blue=cautious,
//                   red=reckless), Squad A/B state, SW1 indicator.
//   rows 24..419  : 2D tactical map. In V2 mode Marines are coloured by squad state
//                   (green=ATTACK, yellow=REGROUP, blue=FALLBACK, orange=last-stand ATTACK;
//                   Squad B has a white center dot); magenta crosshairs mark REGROUP rally points
//                   and cyan crosshairs mark FALLBACK retreat points.
//   rows 420..479 : Lanchester strength bars (2 px per strength unit, max 512 px):
//                   Row 1 = Squad A (P_A), Row 2 = Squad B (P_B), Row 3 = Combined (P_AB), Row 4 = Enemy (P_E),
//                   with a vertical white line at the engagement threshold P_T (P_E, 2*P_E or P_E/2).
import sc2fpga_pkg::*;
module vga_render (
  input  logic          clk,
  input  logic [9:0]    x, y,
  input  logic          visible, hsync_n_in, vsync_n_in,
  input  logic [4:0]    n_f, n_e,
  input  logic [CW-1:0] f_x [MAX_UNITS], f_y [MAX_UNITS], e_x [MAX_UNITS], e_y [MAX_UNITS],
  input  logic [MAX_UNITS-1:0] f_squad,
  input  logic [7:0]    target [MAX_UNITS],
  input  logic          policy, error,
  input  logic          v2_mode, regroup_en,
  input  logic [1:0]    state_a, state_b,
  input  logic [11:0]   p_a, p_b, p_ab, p_e, p_t,
  input  logic          last_a, last_b, cautious, reckless, key_roach,
  input  logic [CW-1:0] rally_ax, rally_ay, rally_bx, rally_by,
  output logic [3:0]    r, g, b,
  output logic          hsync_n, vsync_n
);
  function automatic logic [11:0] pal(input logic [2:0] j);
    case (j)
      3'd0: pal = 12'hF22; 3'd1: pal = 12'hFF2; 3'd2: pal = 12'hF2F; 3'd3: pal = 12'hF82;
      3'd4: pal = 12'h2FF; 3'd5: pal = 12'h8F2; 3'd6: pal = 12'hA6F; default: pal = 12'hFFF;
    endcase
  endfunction

  function automatic logic [11:0] st_col(input logic [1:0] st);
    case (st)
      SQ_ATTACK:  st_col = 12'h2F4; // green
      SQ_REGROUP: st_col = 12'hFF0; // yellow
      SQ_FALLBACK: st_col = 12'h38F; // blue
      default:    st_col = 12'h888;
    endcase
  endfunction

  logic [11:0] col_a, col_b;
  assign col_a = last_a ? 12'hF60 : st_col(state_a);
  assign col_b = last_b ? 12'hF60 : st_col(state_b);

  logic signed [12:0] mx, my;
  assign mx = 13'sd368 + $signed({4'b0, x[9:1]});
  assign my = 13'sd568 - $signed({4'b0, y[9:1]});

  // Bar widths: 2 pixels per strength unit, capped at 512 px
  logic [9:0] pa_w, pb_w, pab_w, pe_w, pt_w;
  assign pa_w  = (p_a  > 12'd255) ? 10'd512 : {1'b0, p_a[7:0],  1'b0};
  assign pb_w  = (p_b  > 12'd255) ? 10'd512 : {1'b0, p_b[7:0],  1'b0};
  assign pab_w = (p_ab > 12'd255) ? 10'd512 : {1'b0, p_ab[7:0], 1'b0};
  assign pe_w  = (p_e  > 12'd255) ? 10'd512 : {1'b0, p_e[7:0],  1'b0};
  assign pt_w  = (p_t  > 12'd255) ? 10'd512 : {1'b0, p_t[7:0],  1'b0};

  // ---------- per-line constants ----------
  logic signed [12:0] l_dx [MAX_UNITS], l_dy [MAX_UNITS];
  logic        [11:0] l_len [MAX_UNITS];
  logic signed [12:0] l_x0 [MAX_UNITS], l_x1 [MAX_UNITS], l_y0 [MAX_UNITS], l_y1 [MAX_UNITS];
  logic [MAX_UNITS-1:0] l_on, t_on;
  logic signed [12:0] t_fx [MAX_UNITS], t_fy [MAX_UNITS], t_ex [MAX_UNITS], t_ey [MAX_UNITS];
  // stage L1: select each Marine's target position (static data; extra latency is harmless)
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic [1:0] sq_st;
      sq_st = f_squad[k] ? state_b : state_a;
      t_fx[k] <= $signed({2'b0, f_x[k]}); t_fy[k] <= $signed({2'b0, f_y[k]});
      t_ex[k] <= $signed({2'b0, e_x[target[k][3:0]]}); t_ey[k] <= $signed({2'b0, e_y[target[k][3:0]]});
      t_on[k] <= (k < n_f) && (target[k] != NO_TARGET) && ({1'b0, target[k][3:0]} < n_e) && (!v2_mode || sq_st == SQ_ATTACK);
    end
  end
  // stage L2: line deltas, length and bounding box
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic signed [12:0] fx, fy, ex, ey, dx, dy;
      fx = t_fx[k]; fy = t_fy[k]; ex = t_ex[k]; ey = t_ey[k];
      dx = ex - fx; dy = ey - fy;
      l_dx[k] <= dx; l_dy[k] <= dy;
      l_len[k] <= ((dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy)) ? 12'(dx < 0 ? -dx : dx) : 12'(dy < 0 ? -dy : dy);
      l_x0[k] <= (fx < ex ? fx : ex) - 13'sd1; l_x1[k] <= (fx < ex ? ex : fx) + 13'sd1;
      l_y0[k] <= (fy < ey ? fy : ey) - 13'sd1; l_y1[k] <= (fy < ey ? ey : fy) + 13'sd1;
      l_on[k] <= t_on[k];
    end
  end

  // ---------- HUD combinational color (computed in stage A, pipelined to stage D) ----------
  logic        hud_en_c;
  logic [11:0] hud_col_c;
  always_comb begin
    logic [9:0] bx;
    hud_en_c  = 1'b0;
    hud_col_c = 12'h000;
    bx        = x - 10'd64;
    if (y < 10'd24) begin
      hud_en_c  = 1'b1;
      hud_col_c = error ? 12'hF00 : (policy ? 12'hF80 : 12'h0CC);
      if (y >= 10'd4 && y <= 10'd19) begin
        if (x >= 10'd340 && x < 10'd385)      hud_col_c = key_roach ? 12'hF33 : 12'h2F4;
        else if (x >= 10'd395 && x < 10'd440) hud_col_c = cautious ? 12'h38F : reckless ? 12'hF22 : 12'h888;
        else if (x >= 10'd460 && x < 10'd505) hud_col_c = col_a;
        else if (x >= 10'd515 && x < 10'd560) hud_col_c = col_b;
        else if (x >= 10'd575 && x < 10'd625) hud_col_c = regroup_en ? 12'h0F0 : 12'h333;
      end
    end else if (y >= 10'd420) begin
      hud_en_c  = 1'b1;
      hud_col_c = (y <= 10'd421) ? 12'h556 : 12'h112;
      // Left-side color tags for each bar
      if (x >= 10'd20 && x < 10'd52) begin
        if (y >= 10'd426 && y <= 10'd435)      hud_col_c = col_a;
        else if (y >= 10'd439 && y <= 10'd448) hud_col_c = col_b;
        else if (y >= 10'd452 && y <= 10'd461) hud_col_c = 12'h4FF;
        else if (y >= 10'd465 && y <= 10'd474) hud_col_c = 12'hF33;
      end
      // Strength bars
      if (x >= 10'd64 && x < 10'd576) begin
        if (y >= 10'd426 && y <= 10'd435)      hud_col_c = (bx < pa_w)  ? col_a : 12'h223;
        else if (y >= 10'd439 && y <= 10'd448) hud_col_c = (bx < pb_w)  ? col_b : 12'h223;
        else if (y >= 10'd452 && y <= 10'd461) hud_col_c = (bx < pab_w) ? ((p_ab >= p_t) ? 12'h4FF : 12'h278) : 12'h223;
        else if (y >= 10'd465 && y <= 10'd474) hud_col_c = (bx < pe_w)  ? 12'hF33 : 12'h223;
        // White engagement-threshold marker across all 4 bars
        if (y >= 10'd424 && y <= 10'd476 && (bx == pt_w || bx == pt_w + 10'd1))
          hud_col_c = 12'hFFF;
      end
    end
  end

  // ---------- stage A: marker hit tests, line offsets, rally markers, HUD ----------
  logic [MAX_UNITS-1:0] fhit, fctr, ering, ecore, targeted, l_box;
  logic signed [12:0] l_rx [MAX_UNITS], l_ry [MAX_UNITS];
  logic a_vis, a_hs, a_vs, a_grid, a_hud_en, a_rally, a_retreat;
  logic [11:0] a_hud_col;
  always_comb begin
    targeted = '0;
    for (int k = 0; k < MAX_UNITS; k++)
      if (k < n_f && target[k] != NO_TARGET) targeted[target[k][3:0]] = 1'b1;
  end
  always_ff @(posedge clk) begin
    logic signed [12:0] drax, dray, drbx, drby;
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic signed [12:0] dfx, dfy, dex, dey;
      dfx = mx - $signed({2'b0, f_x[k]});  dfy = my - $signed({2'b0, f_y[k]});
      dex = mx - $signed({2'b0, e_x[k]});  dey = my - $signed({2'b0, e_y[k]});
      fhit[k]  <= (k < n_f) && dfx >= -3 && dfx <= 3 && dfy >= -3 && dfy <= 3;
      fctr[k]  <= (k < n_f) && dfx >= -1 && dfx <= 1 && dfy >= -1 && dfy <= 1;
      ering[k] <= (k < n_e) && dex >= -7 && dex <= 7 && dey >= -7 && dey <= 7 &&
                  !(dex >= -5 && dex <= 5 && dey >= -5 && dey <= 5);
      ecore[k] <= (k < n_e) && targeted[k] && dex >= -2 && dex <= 2 && dey >= -2 && dey <= 2;
      l_rx[k]  <= dfx; l_ry[k] <= dfy;
      l_box[k] <= l_on[k] && mx >= l_x0[k] && mx <= l_x1[k] && my >= l_y0[k] && my <= l_y1[k];
    end
    drax = mx - $signed({2'b0, rally_ax}); dray = my - $signed({2'b0, rally_ay});
    drbx = mx - $signed({2'b0, rally_bx}); drby = my - $signed({2'b0, rally_by});
    begin
      logic xa, xb;
      xa = (drax >= -5 && drax <= 5 && dray == 0) || (dray >= -5 && dray <= 5 && drax == 0);
      xb = (drbx >= -5 && drbx <= 5 && drby == 0) || (drby >= -5 && drby <= 5 && drbx == 0);
      a_rally   <= v2_mode && ((state_a == SQ_REGROUP  && xa) || (state_b == SQ_REGROUP  && xb));
      a_retreat <= v2_mode && ((state_a == SQ_FALLBACK && xa) || (state_b == SQ_FALLBACK && xb));
    end
    a_vis <= visible; a_hs <= hsync_n_in; a_vs <= vsync_n_in;
    a_grid    <= (mx[3:0] == 4'd0 && !x[0]) || (my[3:0] == 4'd0 && !y[0]);
    a_hud_en  <= hud_en_c;
    a_hud_col <= hud_col_c;
  end

  // ---------- stage B: cross-product terms ----------
  logic signed [25:0] l_p1 [MAX_UNITS], l_p2 [MAX_UNITS];
  logic [MAX_UNITS-1:0] b_fhit, b_fctr, b_ering, b_ecore, b_box;
  logic b_vis, b_hs, b_vs, b_grid, b_hud_en, b_rally, b_retreat;
  logic [11:0] b_hud_col;
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      l_p1[k] <= l_rx[k] * l_dy[k];
      l_p2[k] <= l_ry[k] * l_dx[k];
    end
    b_fhit <= fhit; b_fctr <= fctr; b_ering <= ering; b_ecore <= ecore; b_box <= l_box;
    b_vis <= a_vis; b_hs <= a_hs; b_vs <= a_vs; b_grid <= a_grid;
    b_hud_en <= a_hud_en; b_hud_col <= a_hud_col; b_rally <= a_rally; b_retreat <= a_retreat;
  end

  // ---------- stage C: line hit ----------
  logic [MAX_UNITS-1:0] lhit, c_fhit, c_fctr, c_ering, c_ecore;
  logic c_vis, c_hs, c_vs, c_grid, c_hud_en, c_rally, c_retreat;
  logic [11:0] c_hud_col;
  always_ff @(posedge clk) begin
    for (int k = 0; k < MAX_UNITS; k++) begin
      logic signed [26:0] cr;
      cr = 27'(l_p1[k]) - 27'(l_p2[k]);
      lhit[k] <= b_box[k] && ((cr < 0 ? -cr : cr) <= $signed({15'd0, l_len[k]}));
    end
    c_fhit <= b_fhit; c_fctr <= b_fctr; c_ering <= b_ering; c_ecore <= b_ecore;
    c_vis <= b_vis; c_hs <= b_hs; c_vs <= b_vs; c_grid <= b_grid;
    c_hud_en <= b_hud_en; c_hud_col <= b_hud_col; c_rally <= b_rally; c_retreat <= b_retreat;
  end

  // ---------- stage D: per-layer priority select (lowest index wins, as before) ----------
  logic        d_line, d_enemy, d_friend;
  logic [11:0] d_lcol, d_ecol, d_fcol;
  logic d_vis, d_hs, d_vs, d_grid, d_hud_en, d_rally, d_retreat;
  logic [11:0] d_hud_col;
  always_ff @(posedge clk) begin
    logic [11:0] lc;
    d_line <= 1'b0; d_enemy <= 1'b0; d_friend <= 1'b0;
    d_lcol <= 12'h000; d_ecol <= 12'h000; d_fcol <= 12'h000;
    for (int k = MAX_UNITS - 1; k >= 0; k--)
      if (lhit[k]) begin d_line <= 1'b1; lc = pal(target[k][2:0]); d_lcol <= {1'b0, lc[11:9], 1'b0, lc[7:5], 1'b0, lc[3:1]}; end
    for (int k = MAX_UNITS - 1; k >= 0; k--)
      if (c_ering[k] || c_ecore[k]) begin d_enemy <= 1'b1; d_ecol <= pal(k[2:0]); end
    for (int k = MAX_UNITS - 1; k >= 0; k--)
      if (c_fhit[k]) begin
        d_friend <= 1'b1;
        if (v2_mode)
          d_fcol <= (f_squad[k] && c_fctr[k]) ? 12'hFFF : (f_squad[k] ? col_b : col_a);
        else
          d_fcol <= (target[k] == NO_TARGET) ? 12'h888 : pal(target[k][2:0]);
      end
    d_vis <= c_vis; d_hs <= c_hs; d_vs <= c_vs; d_grid <= c_grid;
    d_hud_en <= c_hud_en; d_hud_col <= c_hud_col; d_rally <= c_rally; d_retreat <= c_retreat;
  end

  // ---------- stage E: compose ----------
  always_ff @(posedge clk) begin
    logic [11:0] c;
    c = d_grid ? 12'h222 : 12'h000;
    if (d_line)   c = d_lcol;
    if (d_enemy)  c = d_ecol;
    if (d_friend) c = d_fcol;
    if (d_retreat) c = 12'h0FF;
    if (d_rally)  c = 12'hF0F;
    if (d_hud_en) c = d_hud_col;
    if (!d_vis) c = 12'h000;
    {r, g, b} <= c;
    hsync_n <= d_hs; vsync_n <= d_vs;
  end
endmodule
