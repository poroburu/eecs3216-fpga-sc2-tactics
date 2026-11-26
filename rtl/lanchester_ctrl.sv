// Lanchester's square-law strength evaluator and two-squad tactical FSM.
//
//   P_A  = K_MARINE * n_a^2          (K_MARINE = 1)
//   P_B  = K_MARINE * n_b^2
//   P_AB = K_MARINE * (n_a + n_b)^2
//   P_E  = K_ROACH  * n_e^2          (K_ROACH = 4, about Roach/Marine dps*hp)
//   P_T  = engagement threshold: P_E (tuned), 2*P_E (SW3 cautious) or P_E/2 (SW4 reckless)
//
// Squad states (per squad A/B):
//   2'd0 = ATTACK   : fight using target_select output
//   2'd1 = REGROUP  : too weak alone, other squad alive and apart: move to its centroid
//   2'd2 = FALLBACK : too weak even combined (or alone): retreat FALLBACK_STEP away from the
//                     enemy centroid (point latched on entry). After FB_TIMEOUT decisions in
//                     FALLBACK the squad commits to a last-stand ATTACK, which is released by a
//                     new wave (more enemies) or reinforcements (more friendlies in that squad).
//
// Sequential datapath (meets 50 MHz): eval -> 16 accumulate cycles -> multiply -> centroid ->
// distance -> FSM, `done` pulses 21 cycles after `eval`. Inputs must stay stable meanwhile
// (frame_rx does not accept a new frame until the reply has been sent).
import sc2fpga_pkg::*;
module lanchester_ctrl #(
  parameter int HYST_MARGIN   = 8,      // margin to re-enter ATTACK from REGROUP/FALLBACK
  parameter int REGROUP_DIST2 = 6400,   // (5.0 map units * 16)^2 in Q.4 units^2
  parameter int FALLBACK_STEP = 96,     // 6.0 map units in Q.4
  parameter int FB_TIMEOUT    = 28      // decisions (8 game loops each, ~10 s) before a last stand
) (
  input  logic           clk,
  input  logic           rst,
  input  logic           eval,          // 1-cycle pulse when a new V2 snapshot is committed
  input  logic           regroup_en,    // SW1: 0 = force ATTACK, 1 = enable Lanchester FSM
  input  logic           cautious,      // SW3: threshold 2*P_E
  input  logic           reckless,      // SW4: threshold P_E/2 (cautious wins if both)
  input  logic [4:0]     n_f, n_e,
  input  logic [CW-1:0]  f_x [MAX_UNITS], f_y [MAX_UNITS],
  input  logic [CW-1:0]  e_x [MAX_UNITS], e_y [MAX_UNITS],
  input  logic [MAX_UNITS-1:0] f_squad, // 0 = Squad A, 1 = Squad B

  output logic [1:0]     state_a, state_b,
  output logic           last_a, last_b,     // squad is in a committed last-stand ATTACK
  output logic [11:0]    p_a, p_b, p_ab, p_e, p_t,
  output logic [CW-1:0]  rally_ax, rally_ay, // REGROUP: other squad's centroid; FALLBACK: retreat point
  output logic [CW-1:0]  rally_bx, rally_by,
  output logic           together,
  output logic           done                // 1-cycle pulse when outputs are updated
);
  function automatic logic [8:0] sq_lut(input logic [4:0] n);
    sq_lut = (n > 5'd16) ? 9'd256 : 9'(n) * 9'(n);   // constant-folded per n by synthesis
  endfunction

  // Fixed-point reciprocal: round(32768 / n) for division-free centroids
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

  function automatic logic [CW-1:0] round_clamp(input logic [30:0] prod);
    logic [30:0] r;
    r = prod + 31'd16384;
    round_clamp = (r[30:15] > 16'd2047) ? 11'd2047 : r[25:15];
  endfunction

  // Retreat one FALLBACK_STEP along each axis away from the enemy centroid, clamped to the map.
  function automatic logic [CW-1:0] away(input logic [CW-1:0] self_c, input logic [CW-1:0] enemy_c);
    logic signed [12:0] v;
    if (self_c > enemy_c)      v = $signed({2'b0, self_c}) + 13'(FALLBACK_STEP);
    else if (self_c < enemy_c) v = $signed({2'b0, self_c}) - 13'(FALLBACK_STEP);
    else                       v = $signed({2'b0, self_c});
    away = (v < 0) ? '0 : (v > 13'sd2047) ? 11'd2047 : v[CW-1:0];
  endfunction

  function automatic logic [1:0] rule(
    input logic [1:0]  cur,
    input logic [4:0]  n_other,
    input logic        is_together,
    input logic [11:0] p_self, p_comb, p_thr
  );
    logic [12:0] need;
    logic [11:0] p_use;
    need  = (cur == SQ_ATTACK) ? {1'b0, p_thr} : {1'b0, p_thr} + 13'(HYST_MARGIN);
    p_use = is_together ? p_comb : p_self;
    if ({1'b0, p_use} >= need)            rule = SQ_ATTACK;
    else if (!is_together && n_other != 0) rule = SQ_REGROUP;
    else                                   rule = SQ_FALLBACK;
  endfunction

  // ---------------- sequencer ----------------
  typedef enum logic [2:0] {L_IDLE, L_ACC, L_MUL, L_CEN, L_DIST, L_FSM} lstate_t;
  lstate_t ls;
  logic [4:0]  k;
  logic        r_en, r_caut, r_reck;
  logic [4:0]  na, nb, ne;
  logic [14:0] sax, say, sbx, sby, sex, sey;
  logic [30:0] m_ax, m_ay, m_bx, m_by, m_ex, m_ey;
  logic [CW-1:0] cxa, cya, cxb, cyb, cxe, cye;
  logic [11:0] pa_r, pb_r, pab_r, pe_r, pt_r;
  logic [D2W-1:0] d2_ab;

  // per-squad persistent state
  logic [5:0]  fb_cnt_a, fb_cnt_b;
  logic [4:0]  prev_na, prev_nb, prev_ne;
  logic [CW-1:0] fbx_a, fby_a, fbx_b, fby_b;

  logic [3:0] ki;
  assign ki = k[3:0];

  // FSM step for one squad (combinational, used in L_FSM)
  logic [1:0] ns_a, ns_b;
  logic       nl_a, nl_b;
  logic [5:0] nc_a, nc_b;
  logic       tog_c;
  assign tog_c = (na != 0) && (nb != 0) && (d2_ab <= D2W'(REGROUP_DIST2));

  always_comb begin
    logic new_wave;
    new_wave = (ne > prev_ne);
    // Squad A
    nc_a = 6'd0; nl_a = 1'b0;
    if (!r_en || ne == 0 || na == 0) ns_a = SQ_ATTACK;
    else if (last_a && !new_wave && !(na > prev_na)) begin ns_a = SQ_ATTACK; nl_a = 1'b1; end
    else begin
      ns_a = rule(state_a, nb, tog_c, pa_r, pab_r, pt_r);
      if (ns_a == SQ_FALLBACK) begin
        if (fb_cnt_a >= 6'(FB_TIMEOUT - 1)) begin ns_a = SQ_ATTACK; nl_a = 1'b1; end
        else nc_a = fb_cnt_a + 6'd1;
      end
    end
    // Squad B
    nc_b = 6'd0; nl_b = 1'b0;
    if (!r_en || ne == 0 || nb == 0) ns_b = SQ_ATTACK;
    else if (last_b && !new_wave && !(nb > prev_nb)) begin ns_b = SQ_ATTACK; nl_b = 1'b1; end
    else begin
      ns_b = rule(state_b, na, tog_c, pb_r, pab_r, pt_r);
      if (ns_b == SQ_FALLBACK) begin
        if (fb_cnt_b >= 6'(FB_TIMEOUT - 1)) begin ns_b = SQ_ATTACK; nl_b = 1'b1; end
        else nc_b = fb_cnt_b + 6'd1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      ls <= L_IDLE; k <= 0; done <= 0;
      r_en <= 0; r_caut <= 0; r_reck <= 0;
      na <= 0; nb <= 0; ne <= 0;
      sax <= 0; say <= 0; sbx <= 0; sby <= 0; sex <= 0; sey <= 0;
      m_ax <= 0; m_ay <= 0; m_bx <= 0; m_by <= 0; m_ex <= 0; m_ey <= 0;
      cxa <= 0; cya <= 0; cxb <= 0; cyb <= 0; cxe <= 0; cye <= 0;
      pa_r <= 0; pb_r <= 0; pab_r <= 0; pe_r <= 0; pt_r <= 0; d2_ab <= 0;
      state_a <= SQ_ATTACK; state_b <= SQ_ATTACK; last_a <= 0; last_b <= 0;
      fb_cnt_a <= 0; fb_cnt_b <= 0; prev_na <= 0; prev_nb <= 0; prev_ne <= 0;
      fbx_a <= 0; fby_a <= 0; fbx_b <= 0; fby_b <= 0;
      p_a <= 0; p_b <= 0; p_ab <= 0; p_e <= 0; p_t <= 0;
      rally_ax <= 0; rally_ay <= 0; rally_bx <= 0; rally_by <= 0; together <= 0;
    end else begin
      done <= 1'b0;
      case (ls)
        L_IDLE:
          if (eval) begin
            ls <= L_ACC; k <= 0;
            r_en <= regroup_en; r_caut <= cautious; r_reck <= reckless & ~cautious;
            na <= 0; nb <= 0; ne <= n_e;
            sax <= 0; say <= 0; sbx <= 0; sby <= 0; sex <= 0; sey <= 0;
          end
        L_ACC: begin
          if (k < n_f) begin
            if (!f_squad[ki]) begin
              na <= na + 5'd1; sax <= sax + 15'(f_x[ki]); say <= say + 15'(f_y[ki]);
            end else begin
              nb <= nb + 5'd1; sbx <= sbx + 15'(f_x[ki]); sby <= sby + 15'(f_y[ki]);
            end
          end
          if (k < n_e) begin
            sex <= sex + 15'(e_x[ki]); sey <= sey + 15'(e_y[ki]);
          end
          k <= k + 5'd1;
          if (ki == 4'd15) ls <= L_MUL;
        end
        L_MUL: begin
          m_ax <= 31'(sax) * 31'(recip_lut(na)); m_ay <= 31'(say) * 31'(recip_lut(na));
          m_bx <= 31'(sbx) * 31'(recip_lut(nb)); m_by <= 31'(sby) * 31'(recip_lut(nb));
          m_ex <= 31'(sex) * 31'(recip_lut(ne)); m_ey <= 31'(sey) * 31'(recip_lut(ne));
          pa_r  <= 12'(sq_lut(na));
          pb_r  <= 12'(sq_lut(nb));
          pab_r <= 12'(sq_lut(na + nb));
          pe_r  <= {1'b0, sq_lut(ne), 2'b00};     // K_ROACH = 4
          ls <= L_CEN;
        end
        L_CEN: begin
          cxa <= round_clamp(m_ax); cya <= round_clamp(m_ay);
          cxb <= round_clamp(m_bx); cyb <= round_clamp(m_by);
          cxe <= round_clamp(m_ex); cye <= round_clamp(m_ey);
          pt_r <= r_caut ? {pe_r[10:0], 1'b0} : r_reck ? {1'b0, pe_r[11:1]} : pe_r;
          ls <= L_DIST;
        end
        L_DIST: begin
          logic signed [11:0] dx, dy;
          dx = $signed({1'b0, cxa}) - $signed({1'b0, cxb});
          dy = $signed({1'b0, cya}) - $signed({1'b0, cyb});
          d2_ab <= D2W'(dx * dx) + D2W'(dy * dy);
          ls <= L_FSM;
        end
        default: begin // L_FSM
          state_a <= ns_a; state_b <= ns_b;
          last_a <= nl_a; last_b <= nl_b;
          fb_cnt_a <= nc_a; fb_cnt_b <= nc_b;
          prev_na <= na; prev_nb <= nb; prev_ne <= ne;
          // latch retreat points on entry to FALLBACK
          if (ns_a == SQ_FALLBACK && state_a != SQ_FALLBACK) begin fbx_a <= away(cxa, cxe); fby_a <= away(cya, cye); end
          if (ns_b == SQ_FALLBACK && state_b != SQ_FALLBACK) begin fbx_b <= away(cxb, cxe); fby_b <= away(cyb, cye); end
          if (ns_a == SQ_FALLBACK) begin
            rally_ax <= (state_a != SQ_FALLBACK) ? away(cxa, cxe) : fbx_a;
            rally_ay <= (state_a != SQ_FALLBACK) ? away(cya, cye) : fby_a;
          end else begin
            rally_ax <= (nb != 0) ? cxb : cxa;
            rally_ay <= (nb != 0) ? cyb : cya;
          end
          if (ns_b == SQ_FALLBACK) begin
            rally_bx <= (state_b != SQ_FALLBACK) ? away(cxb, cxe) : fbx_b;
            rally_by <= (state_b != SQ_FALLBACK) ? away(cyb, cye) : fby_b;
          end else begin
            rally_bx <= (na != 0) ? cxa : cxb;
            rally_by <= (na != 0) ? cya : cyb;
          end
          p_a <= pa_r; p_b <= pb_r; p_ab <= pab_r; p_e <= pe_r; p_t <= pt_r;
          together <= tog_c;
          done <= 1'b1;
          ls <= L_IDLE;
        end
      endcase
    end
  end
endmodule
