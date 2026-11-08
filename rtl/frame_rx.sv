// Request-frame parser (byte-level FSM).
//
// Request: A5 | snap | nF | nE | reach2_hi | reach2_lo | nF x {x_hi,x_lo,y_hi,y_lo}
//              | nE x {x_hi,x_lo,y_hi,y_lo,hp} | chk
// chk = 8-bit sum of every byte after A5 and before chk.
//
// Bytes are written into STAGING registers. Only a complete frame with a good checksum and
// legal fields is copied (in one clock) into the COMMITTED registers that the datapath reads,
// so a bad or partial frame can never change an in-progress or displayed result.
// While `accept` is low (datapath busy) a completed frame is discarded and `overrun` pulses.
import sc2fpga_pkg::*;
module frame_rx #(parameter int TIMEOUT_CLKS = 500_000) (   // 10 ms at 50 MHz
  input  logic           clk,
  input  logic           rst,
  input  logic [7:0]     rx_data,
  input  logic           rx_valid,
  input  logic           accept,
  // committed snapshot
  output logic [7:0]     snap,
  output logic [4:0]     n_f, n_e,
  output logic [15:0]    reach2,
  output logic [CW-1:0]  f_x [MAX_UNITS], f_y [MAX_UNITS],
  output logic [CW-1:0]  e_x [MAX_UNITS], e_y [MAX_UNITS],
  output logic [7:0]     e_hp [MAX_UNITS],
  output logic           req_ok,           // pulse: committed arrays hold a new snapshot
  output logic           req_err,          // pulse: reply with err_code / err_snap
  output logic [7:0]     err_code,
  output logic [7:0]     err_snap,
  output logic           overrun,
  output logic           busy              // a frame is being received (for LED)
);
  typedef enum logic [3:0] {S_SYNC, S_SNAP, S_NF, S_NE, S_R2H, S_R2L, S_FREC, S_EREC, S_CHK} state_t;
  state_t state;

  // staging copy
  logic [7:0]    s_snap;
  logic [4:0]    s_nf, s_ne;
  logic [15:0]   s_reach2;
  logic [CW-1:0] s_fx [MAX_UNITS], s_fy [MAX_UNITS], s_ex [MAX_UNITS], s_ey [MAX_UNITS];
  logic [7:0]    s_hp [MAX_UNITS];

  logic [7:0]  sum;           // running checksum
  logic [3:0]  idx;           // unit index within the current side
  logic [2:0]  fld;           // byte index within the current record
  logic [2:0]  hi3;           // upper 3 bits of the pending coordinate high byte
  logic        bad_range;     // a coordinate high byte exceeded 7 (value > 2047)
  logic [$clog2(TIMEOUT_CLKS+1)-1:0] idle_cnt;

  assign busy = (state != S_SYNC);

  // count limits checked as soon as both counts are known
  logic [7:0] b;  assign b = rx_data;

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= S_SYNC; req_ok <= 0; req_err <= 0; overrun <= 0; err_code <= 0; err_snap <= 0;
      snap <= 0; n_f <= 0; n_e <= 0; reach2 <= 0; idle_cnt <= 0;
      sum <= 0; idx <= 0; fld <= 0; bad_range <= 0; hi3 <= 0; s_snap <= 0; s_nf <= 0; s_ne <= 0; s_reach2 <= 0;
    end else begin
      req_ok <= 0; req_err <= 0; overrun <= 0;

      // inter-byte timeout while inside a frame
      if (state == S_SYNC || rx_valid) idle_cnt <= 0;
      else if (idle_cnt == TIMEOUT_CLKS) begin
        state <= S_SYNC; req_err <= 1; err_code <= ST_TIMEOUT; err_snap <= s_snap; idle_cnt <= 0;
      end else idle_cnt <= idle_cnt + 1'b1;

      if (rx_valid) begin
        if (state != S_SYNC) sum <= sum + b;
        case (state)
          S_SYNC: if (b == REQ_SYNC) begin
                    state <= S_SNAP; sum <= 0; bad_range <= 0; s_snap <= 0;
                  end
          S_SNAP: begin s_snap <= b; state <= S_NF; end
          S_NF:   begin s_nf <= b[4:0]; state <= S_NE;
                    if (b > MAX_UNITS) begin state <= S_SYNC; req_err <= 1; err_code <= ST_BAD_COUNT; err_snap <= s_snap; end
                  end
          S_NE:   begin s_ne <= b[4:0]; state <= S_R2H;
                    if (b > MAX_UNITS) begin state <= S_SYNC; req_err <= 1; err_code <= ST_BAD_COUNT; err_snap <= s_snap; end
                  end
          S_R2H:  begin s_reach2[15:8] <= b; state <= S_R2L; end
          S_R2L:  begin
                    s_reach2[7:0] <= b; idx <= 0; fld <= 0;
                    state <= (s_nf != 0) ? S_FREC : (s_ne != 0) ? S_EREC : S_CHK;
                  end
          S_FREC: begin                                 // {x_hi, x_lo, y_hi, y_lo}
                    case (fld)
                      3'd0, 3'd2: begin hi3 <= b[2:0]; if (b > 8'd7) bad_range <= 1; end
                      3'd1: s_fx[idx] <= {hi3, b};
                      default: s_fy[idx] <= {hi3, b};
                    endcase
                    if (fld == 3'd3) begin
                      fld <= 0; idx <= idx + 1'b1;
                      if ({1'b0, idx} == s_nf - 1'b1) begin idx <= 0; state <= (s_ne != 0) ? S_EREC : S_CHK; end
                    end else fld <= fld + 1'b1;
                  end
          S_EREC: begin                                 // {x_hi, x_lo, y_hi, y_lo, hp}
                    case (fld)
                      3'd0, 3'd2: begin hi3 <= b[2:0]; if (b > 8'd7) bad_range <= 1; end
                      3'd1: s_ex[idx] <= {hi3, b};
                      3'd3: s_ey[idx] <= {hi3, b};
                      default: s_hp[idx] <= b;
                    endcase
                    if (fld == 3'd4) begin
                      fld <= 0; idx <= idx + 1'b1;
                      if ({1'b0, idx} == s_ne - 1'b1) state <= S_CHK;
                    end else fld <= fld + 1'b1;
                  end
          S_CHK:  begin
                    state <= S_SYNC;
                    if (b != sum)        begin req_err <= 1; err_code <= ST_BAD_CHECKSUM; err_snap <= s_snap; end
                    else if (bad_range)  begin req_err <= 1; err_code <= ST_BAD_RANGE;    err_snap <= s_snap; end
                    else if (!accept)    overrun <= 1;
                    else begin                                     // atomic commit
                      req_ok <= 1;
                      snap <= s_snap; n_f <= s_nf; n_e <= s_ne; reach2 <= s_reach2;
                      for (int k = 0; k < MAX_UNITS; k++) begin
                        f_x[k] <= s_fx[k]; f_y[k] <= s_fy[k];
                        e_x[k] <= s_ex[k]; e_y[k] <= s_ey[k]; e_hp[k] <= s_hp[k];
                      end
                    end
                  end
          default: state <= S_SYNC;
        endcase
      end
    end
  end
endmodule
