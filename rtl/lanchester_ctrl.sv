// Lanchester's square-law strength evaluator and two-squad tactical FSM.
//
//   P_A  = K_MARINE * n_a^2
//   P_B  = K_MARINE * n_b^2
//   P_AB = K_MARINE * (n_a + n_b)^2
//   P_E  = K_ROACH  * n_e^2
//
// Squad states (per squad A/B):
//   2'd0 = ATTACK   : fight using target_select output
//   2'd1 = REGROUP  : disengage and move toward the other squad's centroid
//   2'd2 = HOLD     : hold back (weak even when combined, or ally eliminated)
//
// 2-cycle latency from `eval` pulse to `done` pulse (runs in parallel with target_select).
import sc2fpga_pkg::*;
module lanchester_ctrl #(
  parameter int K_MARINE      = 1,
  parameter int K_ROACH       = 4,
  parameter int HYST_MARGIN   = 8,      // margin to re-enter ATTACK from REGROUP/HOLD
  parameter int REGROUP_DIST2 = 6400    // (5.0 map units * 16)^2 in Q.4 units^2
) (
  input  logic           clk,
  input  logic           rst,
  input  logic           eval,          // 1-cycle pulse when a new snapshot is committed
  input  logic           regroup_en,    // SW1: 0 = force ATTACK, 1 = enable Lanchester FSM
  input  logic [4:0]     n_f, n_e,
  input  logic [CW-1:0]  f_x [MAX_UNITS], f_y [MAX_UNITS],
  input  logic [MAX_UNITS-1:0] f_squad, // 0 = Squad A, 1 = Squad B

  output logic [1:0]     state_a, state_b,
  output logic [11:0]    p_a, p_b, p_ab, p_e,
  output logic [CW-1:0]  rally_ax, rally_ay, // target move point for Squad A (Squad B centroid)
  output logic [CW-1:0]  rally_bx, rally_by, // target move point for Squad B (Squad A centroid)
  output logic           together,
  output logic           done                // 1-cycle pulse when outputs are updated
);
  // 17-entry square lookup table: n in 0..16 -> n^2 in 0..256
  function automatic logic [8:0] sq_lut(input logic [4:0] n);
    case (n)
      5'd0:  sq_lut = 9'd0;    5'd1:  sq_lut = 9'd1;
      5'd2:  sq_lut = 9'd4;    5'd3:  sq_lut = 9'd9;
      5'd4:  sq_lut = 9'd16;   5'd5:  sq_lut = 9'd25;
      5'd6:  sq_lut = 9'd36;   5'd7:  sq_lut = 9'd49;
      5'd8:  sq_lut = 9'd64;   5'd9:  sq_lut = 9'd81;
      5'd10: sq_lut = 9'd100;  5'd11: sq_lut = 9'd121;
      5'd12: sq_lut = 9'd144;  5'd13: sq_lut = 9'd169;
      5'd14: sq_lut = 9'd196;  5'd15: sq_lut = 9'd225;
      5'd16: sq_lut = 9'd256;  default: sq_lut = 9'd256;
    endcase
  endfunction

   // Fixed-point reciprocal LUT: round(32768 / n) for exact division-free centroids
   function automatic logic [15:0] recip_lut(input logic [4:0] n);
      case (n)
        5'd1:  recip_lut = 16'd32768; 5'd2:  recip_lut = 16'd16384;
        5'd3:  recip_lut = 16'd10923; 5'd4:  recip_lut = 16'd8192;
        5'd5:  recip_lut = 16'd6554;  5'd6:  recip_lut = 16'd5461;
        5'd7:  recip_lut = 16'd4681;  5'd8:  recip_lut = 16'd4096;
        5'd9:  recip_lut = 16'd3641;  5'd10: recip_lut = 16'd3277;
        5'd11: recip_lut = 16'd2979;  5'd12: recip_lut = 16'd2731;
        5'd13: recip_lut = 16'd2521;  5'd14: recip_lut = 16'd2341;
        5'd15: recip_lut = 16'd2185;  5'd16: recip_lut = 16'd2048;
        default: recip_lut = 16'd0;
      endcase
   endfunction

   function automatic logic [CW-1:0] centroid_div(input logic [14:0] acc, input logic [4:0] cnt);
      logic [30:0] prod;
      logic [15:0] scaled;
      prod   = {16'd0, acc} * {15'd0, recip_lut(cnt)} + 31'd16384;
      scaled = prod[30:15];
      centroid_div = (scaled > 16'd2047) ? 11'd2047 : scaled[CW-1:0];
   endfunction

  function automatic logic [1:0] next_sq_state(
    input logic [1:0]  cur,
    input logic        en,
    input logic [4:0]  n_self, n_other, n_enemy,
    input logic        is_together,
    input logic [11:0] p_self, p_comb, p_enemy
  );
    logic [12:0] thresh_reengage;
    thresh_reengage = {1'b0, p_enemy} + 13'(HYST_MARGIN);

    if (!en || n_enemy == 5'd0 || n_self == 5'd0) begin
      next_sq_state = SQ_ATTACK;
    end else if (is_together) begin
      if (cur == SQ_ATTACK)
        next_sq_state = (p_comb >= p_enemy) ? SQ_ATTACK : SQ_HOLD;
      else
        next_sq_state = ({1'b0, p_comb} >= thresh_reengage) ? SQ_ATTACK : SQ_HOLD;
    end else begin
      if (cur == SQ_ATTACK) begin
        if (p_self >= p_enemy)        next_sq_state = SQ_ATTACK;
        else if (n_other != 5'd0)     next_sq_state = SQ_REGROUP;
        else                          next_sq_state = SQ_HOLD;
      end else begin
        if ({1'b0, p_self} >= thresh_reengage) next_sq_state = SQ_ATTACK;
        else if (n_other != 5'd0)              next_sq_state = SQ_REGROUP;
        else                                   next_sq_state = SQ_HOLD;
      end
    end
  endfunction

  // ---------------- Combinational squad counts, sums, and strengths ----------------
  logic [4:0]  na_c, nb_c, nab_c;
  logic [14:0] sum_ax_c, sum_ay_c, sum_bx_c, sum_by_c;
  logic [11:0] pa_c, pb_c, pab_c, pe_c;

  always_comb begin
    na_c = 5'd0; nb_c = 5'd0;
    sum_ax_c = 15'd0; sum_ay_c = 15'd0;
    sum_bx_c = 15'd0; sum_by_c = 15'd0;
    for (int k = 0; k < MAX_UNITS; k++) begin
      if (k < n_f) begin
        if (!f_squad[k]) begin
          na_c     = na_c + 5'd1;
          sum_ax_c = sum_ax_c + {4'd0, f_x[k]};
          sum_ay_c = sum_ay_c + {4'd0, f_y[k]};
        end else begin
          nb_c     = nb_c + 5'd1;
          sum_bx_c = sum_bx_c + {4'd0, f_x[k]};
          sum_by_c = sum_by_c + {4'd0, f_y[k]};
        end
      end
    end
    nab_c = na_c + nb_c;
    pa_c  = 12'({3'd0, sq_lut(na_c)}  * 12'(K_MARINE));
    pb_c  = 12'({3'd0, sq_lut(nb_c)}  * 12'(K_MARINE));
    pab_c = 12'({3'd0, sq_lut(nab_c)} * 12'(K_MARINE));
    pe_c  = 12'({3'd0, sq_lut(n_e)}   * 12'(K_ROACH));
  end

  // ---------------- Stage 1 registers: centroids & strengths ----------------
  logic          s1_valid, s1_en;
  logic [4:0]    s1_na, s1_nb, s1_ne;
  logic [11:0]   s1_pa, s1_pb, s1_pab, s1_pe;
  logic [CW-1:0] s1_cxa, s1_cya, s1_cxb, s1_cyb;

  // ---------------- Stage 2 combinational: inter-squad distance ----------------
  logic signed [11:0] dx_ab, dy_ab;
  logic [D2W-1:0]     d2_ab;
  logic               s2_together;

  always_comb begin
    dx_ab = $signed({1'b0, s1_cxa}) -$signed({1'b0, s1_cxb});
    dy_ab = $signed({1'b0, s1_cya}) -$signed({1'b0, s1_cyb});
    d2_ab = D2W'(dx_ab * dx_ab) + D2W'(dy_ab * dy_ab);
    s2_together = (s1_na != 5'd0) && (s1_nb != 5'd0) && (d2_ab <= D2W'(REGROUP_DIST2));
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      s1_valid <= 1'b0; s1_en <= 1'b0;
      s1_na <= 5'd0; s1_nb <= 5'd0; s1_ne <= 5'd0;
      s1_pa <= 12'd0; s1_pb <= 12'd0; s1_pab <= 12'd0; s1_pe <= 12'd0;
      s1_cxa <= '0; s1_cya <= '0; s1_cxb <= '0; s1_cyb <= '0;
      state_a <= SQ_ATTACK; state_b <= SQ_ATTACK;
      p_a <= 12'd0; p_b <= 12'd0; p_ab <= 12'd0; p_e <= 12'd0;
      rally_ax <= '0; rally_ay <= '0; rally_bx <= '0; rally_by <= '0;
      together <= 1'b0; done <= 1'b0;
    end else begin
      done <= 1'b0;

      // Stage 1: latch counts, strengths, and centroids
      s1_valid <= eval;
      if (eval) begin
        s1_en  <= regroup_en;
        s1_na  <= na_c;   s1_nb <= nb_c;   s1_ne <= n_e;
        s1_pa  <= pa_c;   s1_pb <= pb_c;   s1_pab <= pab_c; s1_pe <= pe_c;
        s1_cxa <= centroid_div(sum_ax_c, na_c);
        s1_cya <= centroid_div(sum_ay_c, na_c);
        s1_cxb <= centroid_div(sum_bx_c, nb_c);
        s1_cyb <= centroid_div(sum_by_c, nb_c);
      end

      // Stage 2: evaluate distance and update squad FSMs
      if (s1_valid) begin
        p_a      <= s1_pa;  p_b  <= s1_pb;
        p_ab     <= s1_pab; p_e  <= s1_pe;
        together <= s2_together;
        rally_ax <= (s1_nb != 5'd0) ? s1_cxb : s1_cxa;
        rally_ay <= (s1_nb != 5'd0) ? s1_cyb : s1_cya;
        rally_bx <= (s1_na != 5'd0) ? s1_cxa : s1_cxb;
        rally_by <= (s1_na != 5'd0) ? s1_cya : s1_cyb;
        state_a  <= next_sq_state(state_a, s1_en, s1_na, s1_nb, s1_ne, s2_together, s1_pa, s1_pab, s1_pe);
        state_b  <= next_sq_state(state_b, s1_en, s1_nb, s1_na, s1_ne, s2_together, s1_pb, s1_pab, s1_pe);
        done     <= 1'b1;
      end
    end
  end
endmodule
