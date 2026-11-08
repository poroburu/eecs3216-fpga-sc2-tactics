// Reply-frame serializer.
// Reply: 5A | snap | status | policy | n | n x target | cycles_hi | cycles_lo | chk
// chk = 8-bit sum of every byte after 5A and before chk. Error replies have n = 0.
import sc2fpga_pkg::*;
module frame_tx (
  input  logic        clk,
  input  logic        rst,
  input  logic        start,
  input  logic [7:0]  snap, status,
  input  logic        policy,
  input  logic [4:0]  n,
  input  logic [7:0]  target [MAX_UNITS],
  input  logic [15:0] cycles,
  // byte interface to uart_tx
  output logic        tx_start,
  output logic [7:0]  tx_data,
  input  logic        tx_busy,
  output logic        busy,
  output logic        done
);
  typedef enum logic [3:0] {T_IDLE, T_SYNC, T_SNAP, T_STAT, T_POL, T_N, T_TGT, T_CH, T_CL, T_CHK, T_WAIT} state_t;
  state_t state, after;     // `after` = state to enter once the current byte is accepted
  logic [7:0]  r_snap, r_status, sum;
  logic        r_pol;
  logic [4:0]  r_n, k;
  logic [15:0] r_cyc;
  logic [7:0]  r_tgt [MAX_UNITS];
  logic        wait_busy;   // uart_tx raises busy one clock after tx_start

  assign busy = (state != T_IDLE);

  // byte to send in each state
  logic [7:0] cur;
  always_comb begin
    case (state)
      T_SYNC: cur = RSP_SYNC;
      T_SNAP: cur = r_snap;
      T_STAT: cur = r_status;
      T_POL:  cur = {7'd0, r_pol};
      T_N:    cur = {3'd0, r_n};
      T_TGT:  cur = r_tgt[k[3:0]];
      T_CH:   cur = r_cyc[15:8];
      T_CL:   cur = r_cyc[7:0];
      T_CHK:  cur = sum;
      default: cur = 8'h00;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= T_IDLE; tx_start <= 0; tx_data <= 0; done <= 0; wait_busy <= 0; sum <= 0; k <= 0;
    end else begin
      tx_start <= 0; done <= 0;
      if (state == T_IDLE) begin
        if (start) begin
          r_snap <= snap; r_status <= status; r_pol <= policy; r_n <= n; r_cyc <= cycles;
          for (int q = 0; q < MAX_UNITS; q++) r_tgt[q] <= target[q];
          state <= T_SYNC; k <= 0;
        end
      end else if (state == T_WAIT) begin
        // wait for the UART to take the byte and finish shifting it out
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
          T_N:    after <= (r_n != 0) ? T_TGT : T_CH;
          T_TGT:  begin k <= k + 1'b1; after <= (k + 1'b1 == r_n) ? T_CH : T_TGT; end
          T_CH:   after <= T_CL;
          T_CL:   after <= T_CHK;
          default: after <= T_IDLE;   // T_CHK
        endcase
      end
    end
  end
endmodule
