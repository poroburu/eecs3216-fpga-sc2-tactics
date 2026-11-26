// DE10-Lite top level: UART-connected SC2 target-selection + Lanchester two-squad controller.
//
//   GPIO[0] <- USB-UART adapter TX (FPGA RX)      GPIO[1] -> adapter RX (FPGA TX)
//   SW0     policy: 0 = CLOSEST, 1 = FOCUS
//   SW1     Lanchester guard: 0 = OFF (force ATTACK), 1 = ON (square-law ATTACK/REGROUP/FALLBACK FSM)
//   SW2     KEY unit: 0 = Marines, 1 = Roaches
//   SW3     cautious thresholds: attack only at 2x enemy strength (falls back too readily)
//   SW4     reckless thresholds: attack at 0.5x enemy strength (SW3 wins if both are on)
//   SW8     pause: latches VGA/HEX on the latest decision and holds the UART reply while on
//   SW9     HEX mode: 0 = proposal view (HEX5:4 status, HEX3:0 cycles), 1 = debug view
//   KEY0    add one unit of the SW2 type (on release; reported to the host in the next V2 reply)
//   KEY1    remove one unit of the SW2 type
//   KEY0+1  held together ~1 s: reset (squad states, pending edits, sticky error flags)
//   LEDR0   packet received OK    LEDR1 packet rejected (sticky)    LEDR2 overrun (sticky)
//   LEDR3   SW0 (FOCUS)           LEDR4 SW1 (regroup)               LEDR5 squads together
//   LEDR7:6 Squad A state         LEDR9:8 Squad B state
import sc2fpga_pkg::*;
module sc2fpga_top #(
                     parameter int CLKS_PER_BIT = 434,      // 115200 baud at 50 MHz
                     parameter int TIMEOUT_CLKS = 500_000,  // 10 ms inter-byte timeout
                     parameter int DEBOUNCE_CLKS = 1_000_000,    // 20 ms key debounce
                     parameter int RESET_HOLD_CLKS = 50_000_000  // 1 s both-keys reset
                     ) (
                        input  logic       MAX10_CLK1_50,
                        input  logic [1:0] KEY,
                        input  logic [9:0] SW,
                        output logic [9:0] LEDR,
                        output logic [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
                        output logic [3:0] VGA_R, VGA_G, VGA_B,
                        output logic       VGA_HS, VGA_VS,
                        inout  wire [35:0] GPIO
                        );
   logic clk; assign clk = MAX10_CLK1_50;

   // ---------------- power-on reset, switch synchronizers, keys ----------------
   logic [4:0] por_cnt = '0; logic por;
   always_ff @(posedge clk) if (por_cnt != '1) por_cnt <= por_cnt + 5'd1;
   assign por = (por_cnt != '1);
   logic [9:0] sw_m, sw_s;
   always_ff @(posedge clk) begin sw_m <= SW; sw_s <= sw_m; end

   logic key_rst, ev_new, ev_new_op;
   key_ctrl #(.DEBOUNCE_CLKS(DEBOUNCE_CLKS), .RESET_HOLD_CLKS(RESET_HOLD_CLKS)) u_keys (
                .clk, .rst(por), .key_n(KEY), .reset_req(key_rst), .ev(ev_new), .ev_op(ev_new_op));
   logic [2:0] rst_sync; logic rst;
   always_ff @(posedge clk) rst_sync <= {rst_sync[1:0], por | key_rst};
   assign rst = rst_sync[2] | por;

   // ---------------- UART ----------------
   logic [7:0] rx_data; logic rx_valid;
   logic tx_start, tx_busy, txd; logic [7:0] tx_data;
   uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk, .rst, .rx(GPIO[0]), .data(rx_data), .valid(rx_valid));
   uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (.clk, .rst, .start(tx_start), .data(tx_data), .tx(txd), .busy(tx_busy));
   assign GPIO[0] = 1'bz;
   assign GPIO[1] = txd;
   assign GPIO[35:2] = 'z;

   // ---------------- control FSM ----------------
   typedef enum logic [2:0] {C_IDLE, C_COMPUTE, C_PAUSE, C_REPLY, C_ERROR} ctrl_t;
   ctrl_t ctrl;

   // ---------------- request parser ----------------
   logic is_v2, err_v2;
   logic [7:0] snap, err_code, err_snap; logic [4:0] n_f, n_e; logic [15:0] reach2;
   logic [CW-1:0] f_x [MAX_UNITS], f_y [MAX_UNITS], e_x [MAX_UNITS], e_y [MAX_UNITS];
   logic [MAX_UNITS-1:0] f_squad;
   logic [7:0]           e_hp [MAX_UNITS];
   logic                 req_ok, req_err, overrun, rx_busy;
   frame_rx #(.TIMEOUT_CLKS(TIMEOUT_CLKS)) u_frx (
                                                  .clk, .rst, .rx_data, .rx_valid, .accept(ctrl == C_IDLE),
                                                  .is_v2, .snap, .n_f, .n_e, .reach2, .f_x, .f_y, .f_squad, .e_x, .e_y, .e_hp,
                                                  .req_ok, .req_err, .err_code, .err_snap, .err_v2, .overrun, .busy(rx_busy));

   // ---------------- target selection datapath ----------------
   logic [7:0] target [MAX_UNITS]; logic ts_done, ts_busy, ts_policy, ts_regroup, ts_v2; logic [15:0] cycles;
   target_select u_ts (
                       .clk, .rst, .start(req_ok), .policy(sw_s[0]), .n_f, .n_e, .reach2,
                       .f_x, .f_y, .e_x, .e_y, .e_hp, .target, .done(ts_done), .cycles, .busy(ts_busy));

   // ---------------- Lanchester strength & squad FSM ----------------
   logic [1:0]  lc_sta, lc_stb;
   logic [11:0] lc_pa, lc_pb, lc_pab, lc_pe;
   logic [CW-1:0] lc_rax, lc_ray, lc_rbx, lc_rby;
   logic          lc_tog, lc_done;
   logic [11:0] lc_pt; logic lc_la, lc_lb;
   lanchester_ctrl u_lc (
                         .clk, .rst, .eval(req_ok & is_v2 & (ctrl == C_IDLE)), .regroup_en(sw_s[1]),
                         .cautious(sw_s[3]), .reckless(sw_s[4]),
                         .n_f, .n_e, .f_x, .f_y, .e_x, .e_y, .f_squad,
                         .state_a(lc_sta), .state_b(lc_stb), .last_a(lc_la), .last_b(lc_lb),
                         .p_a(lc_pa), .p_b(lc_pb), .p_ab(lc_pab), .p_e(lc_pe), .p_t(lc_pt),
                         .rally_ax(lc_rax), .rally_ay(lc_ray), .rally_bx(lc_rbx), .rally_by(lc_rby),
                         .together(lc_tog), .done(lc_done));

   // ---------------- reply serializer ----------------
   logic ftx_start, ftx_busy, ftx_done;
   logic r_v2;
   logic [7:0] r_snap, r_status; logic [4:0] r_n;
   frame_tx u_ftx (
                   .clk, .rst, .start(ftx_start), .is_v2(r_v2),
                   .snap(r_snap), .status(r_status), .n(r_n),
                   .flags_lo({ts_reck, ts_caut, ts_regroup, ts_policy}),
                   .flags_hi({lc_lb, lc_la, r_evo, r_evu}), .ev_cnt(r_evc),
                   .target, .state_a(lc_sta), .state_b(lc_stb), .together(lc_tog),
                   .rally_ax(lc_rax), .rally_ay(lc_ray), .rally_bx(lc_rbx), .rally_by(lc_rby),
                   .p_a(lc_pa), .p_b(lc_pb), .p_ab(lc_pab), .p_e(lc_pe),
                   .cycles(r_status == ST_OK ? cycles : 16'd0),
                   .tx_start, .tx_data, .tx_busy, .busy(ftx_busy), .done(ftx_done));

   // ---------------- display registers ----------------
   logic [4:0] d_nf, d_ne; logic d_pol, d_regroup, d_v2, d_err, d_tog;
   logic [7:0] d_snap, d_status;
   logic [15:0] d_cyc;
   logic [CW-1:0] d_fx [MAX_UNITS], d_fy [MAX_UNITS], d_ex [MAX_UNITS], d_ey [MAX_UNITS];
   logic [MAX_UNITS-1:0] d_fsquad;
   logic [7:0]           d_tgt [MAX_UNITS];
   logic [1:0]           d_sta, d_stb;
   logic [11:0]          d_pa, d_pb, d_pab, d_pe;
   logic [CW-1:0]        d_rax, d_ray, d_rbx, d_rby;
   logic                 ok_sticky, err_sticky, ovr_sticky;
   logic                 ts_fin, lc_fin;
   logic                 ts_caut, ts_reck;
   logic [11:0]          d_pt;
   logic                 d_la, d_lb, d_caut, d_reck;
   // pending KEY edits: one kind at a time, count saturates at 7; handed to the next V2 OK reply
   logic [2:0] ev_cnt, r_evc; logic ev_unit, ev_op, r_evu, r_evo;
   logic       ev_take;

   logic                 done_all;
   assign done_all = (ts_fin | ts_done) && (!ts_v2 || lc_fin | lc_done);
   assign ev_take = (ctrl == C_COMPUTE) && done_all && ts_v2;

   always_ff @(posedge clk) begin
      if (rst) begin
         ctrl <= C_IDLE; ftx_start <= 0; r_v2 <= 0; r_snap <= 0; r_status <= 0; r_n <= 0;
         ts_policy <= 0; ts_regroup <= 0; ts_v2 <= 0; ts_fin <= 0; lc_fin <= 0;
         d_nf <= 0; d_ne <= 0; d_pol <= 0; d_regroup <= 0; d_v2 <= 0; d_err <= 0; d_tog <= 0;
         d_snap <= 0; d_status <= 0; d_cyc <= 0; d_fsquad <= '0;
         d_sta <= SQ_ATTACK; d_stb <= SQ_ATTACK;
         d_pa <= 0; d_pb <= 0; d_pab <= 0; d_pe <= 0;
         d_rax <= '0; d_ray <= '0; d_rbx <= '0; d_rby <= '0;
         ok_sticky <= 0; err_sticky <= 0; ovr_sticky <= 0;
         ts_caut <= 0; ts_reck <= 0; d_pt <= 0; d_la <= 0; d_lb <= 0; d_caut <= 0; d_reck <= 0;
         ev_cnt <= 0; ev_unit <= 0; ev_op <= 0; r_evc <= 0; r_evu <= 0; r_evo <= 0;
      end else begin
         ftx_start <= 0;
         if (ev_take) begin
            r_evc <= ev_cnt; r_evu <= ev_unit; r_evo <= ev_op;
            ev_cnt <= ev_new ? 3'd1 : 3'd0;
            if (ev_new) begin ev_unit <= sw_s[2]; ev_op <= ev_new_op; end
         end else if (ev_new) begin
            if (ev_cnt == 0) begin ev_cnt <= 3'd1; ev_unit <= sw_s[2]; ev_op <= ev_new_op; end
            else if (ev_unit == sw_s[2] && ev_op == ev_new_op && ev_cnt != 3'd7) ev_cnt <= ev_cnt + 3'd1;
         end
         case (ctrl)
           C_IDLE:
             if (req_ok) begin
                ctrl <= C_COMPUTE; ts_policy <= sw_s[0]; ts_regroup <= sw_s[1]; ts_v2 <= is_v2;
                ts_caut <= sw_s[3]; ts_reck <= sw_s[4] & ~sw_s[3];
                ts_fin <= 0; lc_fin <= 0;
             end else if (req_err) begin
                ctrl <= C_ERROR; ftx_start <= 1; r_v2 <= err_v2; r_snap <= err_snap; r_status <= err_code; r_n <= 0;
                ts_policy <= sw_s[0]; ts_regroup <= sw_s[1]; ts_caut <= sw_s[3]; ts_reck <= sw_s[4] & ~sw_s[3];
                d_err <= 1; d_status <= err_code; err_sticky <= 1;
             end
           C_COMPUTE: begin
              if (ts_done) ts_fin <= 1;
              if (lc_done) lc_fin <= 1;
              if (done_all) begin
                 r_v2 <= ts_v2; r_snap <= snap; r_status <= ST_OK; r_n <= n_f;
                 d_nf <= n_f; d_ne <= n_e; d_pol <= ts_policy; d_regroup <= ts_regroup; d_v2 <= ts_v2;
                 d_err <= 0; d_snap <= snap; d_status <= ST_OK; d_cyc <= cycles; d_fsquad <= f_squad;
                 d_sta <= lc_sta; d_stb <= lc_stb; d_tog <= lc_tog;
                 d_pa <= lc_pa; d_pb <= lc_pb; d_pab <= lc_pab; d_pe <= lc_pe; d_pt <= lc_pt;
                 d_la <= lc_la; d_lb <= lc_lb; d_caut <= ts_caut; d_reck <= ts_reck;
                 d_rax <= lc_rax; d_ray <= lc_ray; d_rbx <= lc_rbx; d_rby <= lc_rby;
                 ok_sticky <= 1;
                 for (int k = 0; k < MAX_UNITS; k++) begin
                    d_fx[k] <= f_x[k]; d_fy[k] <= f_y[k]; d_ex[k] <= e_x[k]; d_ey[k] <= e_y[k]; d_tgt[k] <= target[k];
                 end
                 if (sw_s[8]) ctrl <= C_PAUSE;
                 else begin ctrl <= C_REPLY; ftx_start <= 1; end
              end
           end
           C_PAUSE:
             if (!sw_s[8]) begin ctrl <= C_REPLY; ftx_start <= 1; end
           default:
             if (ftx_done) ctrl <= C_IDLE;
         endcase
         if (overrun) ovr_sticky <= 1;
      end
   end

   // ---------------- HEX / LED ----------------
   logic [4:0] h5_c, h4_c, h3_c, h2_c, h1_c, h0_c;
   always_comb begin
      if (!sw_s[9]) begin
         // Proposal view: HEX5:4 = last error code, HEX3:0 = clock cycles per decision
         h5_c = {1'b0, d_status[7:4]};
         h4_c = {1'b0, d_status[3:0]};
         h3_c = {1'b0, d_cyc[15:12]};
         h2_c = {1'b0, d_cyc[11:8]};
         h1_c = {1'b0, d_cyc[7:4]};
         h0_c = {1'b0, d_cyc[3:0]};
      end else begin
         // Debug view: HEX5:4 = snap, HEX3 = policy (C/F), HEX2 = status, HEX1:0 = state A / state B
         h5_c = {1'b0, d_snap[7:4]};
         h4_c = {1'b0, d_snap[3:0]};
         h3_c = d_pol ? 5'd15 : 5'd12;
         h2_c = {1'b0, d_status[3:0]};
         h1_c = {3'd0, d_sta};
         h0_c = {3'd0, d_stb};
      end
   end
   hex7seg u_h5 (.code(h5_c), .seg(HEX5));
   hex7seg u_h4 (.code(h4_c), .seg(HEX4));
   hex7seg u_h3 (.code(h3_c), .seg(HEX3));
   hex7seg u_h2 (.code(h2_c), .seg(HEX2));
   hex7seg u_h1 (.code(h1_c), .seg(HEX1));
   hex7seg u_h0 (.code(h0_c), .seg(HEX0));

   assign LEDR = {d_stb, d_sta, d_tog, sw_s[1], sw_s[0], ovr_sticky, err_sticky, ok_sticky};

   // ---------------- VGA ----------------
   logic pix_en; logic [9:0] vx, vy; logic vis, hs, vs;
   always_ff @(posedge clk) pix_en <= rst ? 1'b0 : ~pix_en;
   vga_timing u_vt (.clk, .rst, .pix_en, .x(vx), .y(vy), .visible(vis), .hsync_n(hs), .vsync_n(vs));
   vga_render u_vr (
                    .clk, .x(vx), .y(vy), .visible(vis), .hsync_n_in(hs), .vsync_n_in(vs),
                    .n_f(d_nf), .n_e(d_ne), .f_x(d_fx), .f_y(d_fy), .e_x(d_ex), .e_y(d_ey), .f_squad(d_fsquad),
                    .target(d_tgt), .policy(d_pol), .error(d_err),
                    .v2_mode(d_v2), .regroup_en(d_regroup), .state_a(d_sta), .state_b(d_stb),
                    .p_a(d_pa), .p_b(d_pb), .p_ab(d_pab), .p_e(d_pe), .p_t(d_pt),
                    .last_a(d_la), .last_b(d_lb), .cautious(d_caut), .reckless(d_reck), .key_roach(sw_s[2]),
                    .rally_ax(d_rax), .rally_ay(d_ray), .rally_bx(d_rbx), .rally_by(d_rby),
                    .r(VGA_R), .g(VGA_G), .b(VGA_B), .hsync_n(VGA_HS), .vsync_n(VGA_VS));
endmodule
