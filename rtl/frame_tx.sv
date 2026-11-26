// Reply-frame serializer, supporting V1 (5A) and V2 Lanchester (5B).
//
// V1 Reply: 5A | snap | status | policy | n | n x target | cycles_hi | cycles_lo | chk
// V2 Reply: 5B | snap | status | flags  | n | n x target | meta | rally_a(4) | rally_b(4)
//              | p_a(2) | p_b(2) | p_ab(2) | p_e(2) | cycles(2) | chk
//   flags = {last_b, last_a, ev_op, ev_unit, reckless, cautious, regroup_en, policy}
//           (bits 7:4 only in OK replies; error replies send 4'd0 there)
//   meta  = {ev_cnt[2:0], together, state_b[1:0], state_a[1:0]}
//   ev_*  : pending KEY0/KEY1 unit edits since the last V2 OK reply
//           (ev_unit 0 = Marine, 1 = Roach; ev_op 0 = add, 1 = remove; ev_cnt 0 = none, 1..7)
import sc2fpga_pkg::*;
module frame_tx (
  input  logic          clk,
  input  logic          rst,
  input  logic          start,
  input  logic          is_v2,
  input  logic [7:0]    snap, status,
  input  logic [3:0]    flags_lo,      // {reckless, cautious, regroup_en, policy}
  input  logic [3:0]    flags_hi,      // {last_b, last_a, ev_op, ev_unit}
  input  logic [2:0]    ev_cnt,
  input  logic [4:0]    n,
  input  logic [7:0]    target [MAX_UNITS],
  input  logic [1:0]    state_a, state_b,
  input  logic          together,
  input  logic [CW-1:0] rally_ax, rally_ay, rally_bx, rally_by,
  input  logic [11:0]   p_a, p_b, p_ab, p_e,
  input  logic [15:0]   cycles,
  // byte interface to uart_tx
  output logic          tx_start,
  output logic [7:0]    tx_data,
  input  logic          tx_busy,
  output logic          busy,
  output logic          done
);
  typedef enum logic [3:0] {T_IDLE, T_SYNC, T_SNAP, T_STAT, T_POL, T_N, T_TGT, T_EXT, T_CH, T_CL, T_CHK, T_WAIT} state_t;
  state_t state, after;
  logic        r_v2;
  logic [7:0]  r_snap, r_status, r_flags, r_meta, sum;
  logic [4:0]  r_n, k, ext_k;
  logic [15:0] r_cyc;
  logic [7:0]  r_tgt [MAX_UNITS];
  logic [CW-1:0] r_rax, r_ray, r_rbx, r_rby;
  logic [11:0]   r_pa, r_pb, r_pab, r_pe;
  logic        wait_busy;

  assign busy = (state != T_IDLE);

  logic [7:0] cur;
  always_comb begin
    case (state)
      T_SYNC: cur = r_v2 ? RSP_SYNC_V2 : RSP_SYNC;
      T_SNAP: cur = r_snap;
      T_STAT: cur = r_status;
      T_POL:  cur = r_flags;
      T_N:    cur = {3'd0, r_n};
      T_TGT:  cur = r_tgt[k[3:0]];
      T_EXT: begin
        case (ext_k)
          5'd0:  cur = r_meta;
          5'd1:  cur = {5'd0, r_rax[10:8]};
          5'd2:  cur = r_rax[7:0];
          5'd3:  cur = {5'd0, r_ray[10:8]};
          5'd4:  cur = r_ray[7:0];
          5'd5:  cur = {5'd0, r_rbx[10:8]};
          5'd6:  cur = r_rbx[7:0];
          5'd7:  cur = {5'd0, r_rby[10:8]};
          5'd8:  cur = r_rby[7:0];
          5'd9:  cur = {4'd0, r_pa[11:8]};
          5'd10: cur = r_pa[7:0];
          5'd11: cur = {4'd0, r_pb[11:8]};
          5'd12: cur = r_pb[7:0];
          5'd13: cur = {4'd0, r_pab[11:8]};
          5'd14: cur = r_pab[7:0];
          5'd15: cur = {4'd0, r_pe[11:8]};
          default: cur = r_pe[7:0];
        endcase
      end
      T_CH:   cur = r_cyc[15:8];
      T_CL:   cur = r_cyc[7:0];
      T_CHK:  cur = sum;
      default: cur = 8'h00;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= T_IDLE; tx_start <= 0; tx_data <= 0; done <= 0; wait_busy <= 0; sum <= 0; k <= 0; ext_k <= 0;
      r_v2 <= 0; r_snap <= 0; r_status <= 0; r_flags <= 0; r_meta <= 0; r_n <= 0; r_cyc <= 0;
      r_rax <= '0; r_ray <= '0; r_rbx <= '0; r_rby <= '0; r_pa <= '0; r_pb <= '0; r_pab <= '0; r_pe <= '0;
    end else begin
      tx_start <= 0; done <= 0;
      if (state == T_IDLE) begin
        if (start) begin
          r_v2 <= is_v2; r_snap <= snap; r_status <= status;
          r_flags <= is_v2 ? {(status == ST_OK) ? flags_hi : 4'd0, flags_lo} : {7'd0, flags_lo[0]};
          r_n <= n; r_cyc <= cycles;
          for (int q = 0; q < MAX_UNITS; q++) r_tgt[q] <= target[q];
          if (is_v2 && status == ST_OK) begin
            r_meta <= {ev_cnt, together, state_b, state_a};
            r_rax <= rally_ax; r_ray <= rally_ay; r_rbx <= rally_bx; r_rby <= rally_by;
            r_pa <= p_a; r_pb <= p_b; r_pab <= p_ab; r_pe <= p_e;
          end else begin
            r_meta <= 8'd0;
            r_rax <= '0; r_ray <= '0; r_rbx <= '0; r_rby <= '0;
            r_pa <= '0; r_pb <= '0; r_pab <= '0; r_pe <= '0;
          end
          state <= T_SYNC; k <= 0; ext_k <= 0;
        end
      end else if (state == T_WAIT) begin
        if (wait_busy) wait_busy <= 0;
        else if (!tx_busy) begin
          state <= after;
          if (after == T_IDLE) done <= 1;
        end
      end else begin
        tx_start <= 1; tx_data <= cur; wait_busy <= 1; state <= T_WAIT;
        if (state == T_SYNC) sum <= 0; else sum <= sum + cur;
        case (state)
          T_SYNC: after <= T_SNAP;
          T_SNAP: after <= T_STAT;
          T_STAT: after <= T_POL;
          T_POL:  after <= T_N;
          T_N:    after <= (r_n != 0) ? T_TGT : (r_v2 ? T_EXT : T_CH);
          T_TGT:  begin k <= k + 1'b1; after <= (k + 1'b1 == r_n) ? (r_v2 ? T_EXT : T_CH) : T_TGT; end
          T_EXT:  begin
                    if (ext_k == 5'd16) after <= T_CH;
                    else begin ext_k <= ext_k + 1'b1; after <= T_EXT; end
                  end
          T_CH:   after <= T_CL;
          T_CL:   after <= T_CHK;
          default: after <= T_IDLE;
        endcase
      end
    end
  end
endmodule
