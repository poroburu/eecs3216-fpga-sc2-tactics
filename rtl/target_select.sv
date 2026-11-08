// Target-selection datapath: for every friendly unit i, pick the enemy j with the smallest key.
//
//   d2  = (fx_i - ex_j)^2 + (fy_i - ey_j)^2                      (exact integer, 23 bits)
//   in  = d2 <= reach2
//   policy 0 (CLOSEST): key = {1'b0,     8'd0,           d2, j}
//   policy 1 (FOCUS)  : key = {!in,      in ? hp_j : 0,  d2, j}
//
// Comparing the concatenated key as one unsigned number IS the lexicographic rule:
// in-range first, then lowest HP, then nearest, then lowest index (so ties are deterministic).
//
// 3-stage pipeline, one (i,j) pair enters per clock, i-major order:
//   S1 DIFF  : dx = fx_i - ex_j, dy = fy_i - ey_j            (signed 12-bit subtractors)
//   S2 SQUARE: d2 = dx*dx + dy*dy                             (embedded multipliers + adder)
//   S3 SELECT: build key, running minimum per i; on the last j write target[i]
// Cycle count (start -> done) is exactly nF*nE + 3, or 1 when nF or nE is 0.
import sc2fpga_pkg::*;
module target_select (
  input  logic           clk,
  input  logic           rst,
  input  logic           start,
  input  logic           policy,
  input  logic [4:0]     n_f, n_e,
  input  logic [15:0]    reach2,
  input  logic [CW-1:0]  f_x [MAX_UNITS], f_y [MAX_UNITS],
  input  logic [CW-1:0]  e_x [MAX_UNITS], e_y [MAX_UNITS],
  input  logic [7:0]     e_hp [MAX_UNITS],
  output logic [7:0]     target [MAX_UNITS],   // enemy index, or NO_TARGET
  output logic           done,                 // 1-cycle pulse
  output logic [15:0]    cycles,
  output logic           busy
);
  // ---------------- issue counters ----------------
  logic       issuing;
  logic [3:0] ii, jj;
  logic       pol;                    // policy latched at start
  logic [15:0] cyc;

  // ---------------- pipeline registers ----------------
  logic              v1, v2;
  logic [3:0]        i1, j1, i2, j2;
  logic              first1, last1, final1, first2, last2, final2;  // first/last j of this i, last pair overall
  logic signed [11:0] dx1, dy1;
  logic [7:0]        hp1, hp2;
  logic [D2W-1:0]    d2_2;

  // ---------------- S3 state ----------------
  logic [KEYW-1:0]   best;
  logic [KEYW-1:0]   key;
  logic              inr;

  assign busy = issuing | v1 | v2;

  // S3 key construction (combinational)
  always_comb begin
    inr = (d2_2 <= {7'd0, reach2});
    if (pol) key = {~inr, (inr ? hp2 : 8'd0), d2_2, j2};
    else     key = {1'b0, 8'd0,               d2_2, j2};
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      issuing <= 0; v1 <= 0; v2 <= 0; done <= 0; cycles <= 0; cyc <= 0; ii <= 0; jj <= 0; pol <= 0;
      for (int k = 0; k < MAX_UNITS; k++) target[k] <= NO_TARGET;
    end else begin
      done <= 0;
      if (busy) cyc <= cyc + 1'b1;

      // ---- start / issue ----
      if (start && !busy) begin
        pol <= policy; cyc <= 16'd1; ii <= 0; jj <= 0;
        for (int k = 0; k < MAX_UNITS; k++) target[k] <= NO_TARGET;
        if (n_f == 0 || n_e == 0) begin done <= 1; cycles <= 16'd1; end
        else issuing <= 1;
      end else if (issuing) begin
        if ({1'b0, jj} == n_e - 1'b1) begin
          jj <= 0;
          if ({1'b0, ii} == n_f - 1'b1) issuing <= 0; else ii <= ii + 1'b1;
        end else jj <= jj + 1'b1;
      end

      // ---- S1: DIFF ----
      v1     <= issuing;
      i1     <= ii;  j1 <= jj;
      first1 <= (jj == 0);
      last1  <= ({1'b0, jj} == n_e - 1'b1);
      final1 <= ({1'b0, jj} == n_e - 1'b1) && ({1'b0, ii} == n_f - 1'b1);
      dx1    <= $signed({1'b0, f_x[ii]}) - $signed({1'b0, e_x[jj]});
      dy1    <= $signed({1'b0, f_y[ii]}) - $signed({1'b0, e_y[jj]});
      hp1    <= e_hp[jj];

      // ---- S2: SQUARE ----
      v2     <= v1;
      i2     <= i1; j2 <= j1; first2 <= first1; last2 <= last1; final2 <= final1; hp2 <= hp1;
      d2_2   <= D2W'(dx1 * dx1) + D2W'(dy1 * dy1);

      // ---- S3: SELECT ----
      if (v2) begin
        if (first2 || key < best) best <= key;
        if (last2) target[i2] <= {4'd0, ((first2 || key < best) ? j2 : best[3:0])};
        if (final2) begin done <= 1; cycles <= cyc; end
      end
    end
  end
endmodule
