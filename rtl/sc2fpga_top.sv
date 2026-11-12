// DE10-Lite top level: UART-connected target-selection coprocessor with VGA/HEX/LED status.
//
//   GPIO[0]  <- USB-UART adapter TX (FPGA RX)      GPIO[1] -> adapter RX (FPGA TX)
//   SW0      policy: 0 = CLOSEST, 1 = FOCUS (sampled at the start of each computation)
//   SW4..SW1 friendly unit k shown on HEX1 (k) / HEX0 (its target, '-' = none)
//   KEY0     reset (active low)      KEY1  clear sticky error/overrun LEDs
//   HEX5:4 snapshot id   HEX3 policy (C/F)   HEX2 last status code (0 = OK)
//   LEDR0 policy  LEDR1 receiving  LEDR2 sticky error  LEDR3 sticky overrun  LEDR9:4 #distinct targets
//
// Control FSM:  IDLE --req_ok--> COMPUTE --done--> REPLY --tx done--> IDLE
//               IDLE --req_err-------------------> ERROR --tx done--> IDLE
import sc2fpga_pkg::*;
module sc2fpga_top #(
  parameter int CLKS_PER_BIT = 434,      // 115200 baud at 50 MHz
  parameter int TIMEOUT_CLKS = 500_000   // 10 ms inter-byte timeout
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

  // ---------------- reset and switch synchronizers ----------------
  logic [2:0] rst_sync; logic rst;
  always_ff @(posedge clk) rst_sync <= {rst_sync[1:0], ~KEY[0]};
  assign rst = rst_sync[2];
  logic [9:0] sw_m, sw_s; logic [1:0] key1_s;
  always_ff @(posedge clk) begin sw_m <= SW; sw_s <= sw_m; key1_s <= {key1_s[0], ~KEY[1]}; end

  // ---------------- UART ----------------
  logic [7:0] rx_data; logic rx_valid;
  logic tx_start, tx_busy, txd; logic [7:0] tx_data;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk, .rst, .rx(GPIO[0]), .data(rx_data), .valid(rx_valid));
  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (.clk, .rst, .start(tx_start), .data(tx_data), .tx(txd), .busy(tx_busy));
  assign GPIO[0] = 1'bz;
  assign GPIO[1] = txd;
  assign GPIO[35:2] = 'z;

  // ---------------- control FSM ----------------
  typedef enum logic [1:0] {C_IDLE, C_COMPUTE, C_REPLY, C_ERROR} ctrl_t;
  ctrl_t ctrl;

  // ---------------- request parser ----------------
  logic [7:0] snap, err_code, err_snap; logic [4:0] n_f, n_e; logic [15:0] reach2;
  logic [CW-1:0] f_x [MAX_UNITS], f_y [MAX_UNITS], e_x [MAX_UNITS], e_y [MAX_UNITS];
  logic [7:0] e_hp [MAX_UNITS];
  logic req_ok, req_err, overrun, rx_busy;
  frame_rx #(.TIMEOUT_CLKS(TIMEOUT_CLKS)) u_frx (
    .clk, .rst, .rx_data, .rx_valid, .accept(ctrl == C_IDLE),
    .snap, .n_f, .n_e, .reach2, .f_x, .f_y, .e_x, .e_y, .e_hp,
    .req_ok, .req_err, .err_code, .err_snap, .overrun, .busy(rx_busy));

  // ---------------- datapath ----------------
  logic [7:0] target [MAX_UNITS]; logic ts_done, ts_busy, ts_policy; logic [15:0] cycles;
  target_select u_ts (
    .clk, .rst, .start(req_ok), .policy(sw_s[0]), .n_f, .n_e, .reach2,
    .f_x, .f_y, .e_x, .e_y, .e_hp, .target, .done(ts_done), .cycles, .busy(ts_busy));
  always_ff @(posedge clk) if (req_ok) ts_policy <= sw_s[0];   // policy actually used

  // ---------------- reply ----------------
  logic ftx_start, ftx_busy, ftx_done;
  logic [7:0] r_snap, r_status; logic [4:0] r_n;
  frame_tx u_ftx (
    .clk, .rst, .start(ftx_start), .snap(r_snap), .status(r_status), .policy(ts_policy), .n(r_n),
    .target, .cycles(r_status == ST_OK ? cycles : 16'd0),
    .tx_start, .tx_data, .tx_busy, .busy(ftx_busy), .done(ftx_done));

  // ---------------- display registers (copied when a result is final) ----------------
  logic [4:0] d_nf, d_ne; logic d_pol, d_err; logic [7:0] d_snap, d_status;
  logic [CW-1:0] d_fx [MAX_UNITS], d_fy [MAX_UNITS], d_ex [MAX_UNITS], d_ey [MAX_UNITS];
  logic [7:0] d_tgt [MAX_UNITS];
  logic err_sticky, ovr_sticky;

  always_ff @(posedge clk) begin
    if (rst) begin
      ctrl <= C_IDLE; ftx_start <= 0; r_snap <= 0; r_status <= 0; r_n <= 0;
      d_nf <= 0; d_ne <= 0; d_pol <= 0; d_err <= 0; d_snap <= 0; d_status <= 0;
      err_sticky <= 0; ovr_sticky <= 0;
    end else begin
      ftx_start <= 0;
      case (ctrl)
        C_IDLE:
          if (req_ok) ctrl <= C_COMPUTE;
          else if (req_err) begin
            ctrl <= C_ERROR; ftx_start <= 1; r_snap <= err_snap; r_status <= err_code; r_n <= 0;
            d_err <= 1; d_status <= err_code; err_sticky <= 1;
          end
        C_COMPUTE:
          if (ts_done) begin
            ctrl <= C_REPLY; ftx_start <= 1; r_snap <= snap; r_status <= ST_OK; r_n <= n_f;
            d_nf <= n_f; d_ne <= n_e; d_pol <= ts_policy; d_err <= 0; d_snap <= snap; d_status <= ST_OK;
            for (int k = 0; k < MAX_UNITS; k++) begin
              d_fx[k] <= f_x[k]; d_fy[k] <= f_y[k]; d_ex[k] <= e_x[k]; d_ey[k] <= e_y[k]; d_tgt[k] <= target[k];
            end
          end
        default: if (ftx_done) ctrl <= C_IDLE;      // C_REPLY, C_ERROR
      endcase
      if (overrun) ovr_sticky <= 1;
      if (key1_s[1]) begin err_sticky <= 0; ovr_sticky <= 0; end
    end
  end

  // ---------------- HEX / LED ----------------
  logic [3:0] sel; assign sel = sw_s[4:1];
  logic [4:0] h0;
  always_comb h0 = ({1'b0, sel} >= d_nf || d_tgt[sel] == NO_TARGET) ? 5'd17 : {1'b0, d_tgt[sel][3:0]};
  hex7seg u_h5 (.code({1'b0, d_snap[7:4]}), .seg(HEX5));
  hex7seg u_h4 (.code({1'b0, d_snap[3:0]}), .seg(HEX4));
  hex7seg u_h3 (.code(d_pol ? 5'd15 : 5'd12), .seg(HEX3));    // 'F' or 'C'
  hex7seg u_h2 (.code({1'b0, d_status[3:0]}), .seg(HEX2));
  hex7seg u_h1 (.code({1'b0, sel}), .seg(HEX1));
  hex7seg u_h0 (.code(h0), .seg(HEX0));

  logic [MAX_UNITS-1:0] tmask; logic [4:0] ndist;
  always_comb begin
    tmask = '0; ndist = 0;
    for (int k = 0; k < MAX_UNITS; k++) if (k < d_nf && d_tgt[k] != NO_TARGET) tmask[d_tgt[k][3:0]] = 1'b1;
    for (int k = 0; k < MAX_UNITS; k++) ndist = ndist + tmask[k];
  end
  logic [5:0] bar;
  always_comb for (int k = 0; k < 6; k++) bar[k] = (ndist > k);
  assign LEDR = {bar, ovr_sticky, err_sticky, rx_busy, sw_s[0]};

  // ---------------- VGA ----------------
  logic pix_en; logic [9:0] vx, vy; logic vis, hs, vs;
  always_ff @(posedge clk) pix_en <= rst ? 1'b0 : ~pix_en;
  vga_timing u_vt (.clk, .rst, .pix_en, .x(vx), .y(vy), .visible(vis), .hsync_n(hs), .vsync_n(vs));
  vga_render u_vr (
    .clk, .x(vx), .y(vy), .visible(vis), .hsync_n_in(hs), .vsync_n_in(vs),
    .n_f(d_nf), .n_e(d_ne), .f_x(d_fx), .f_y(d_fy), .e_x(d_ex), .e_y(d_ey), .target(d_tgt),
    .policy(d_pol), .error(d_err), .r(VGA_R), .g(VGA_G), .b(VGA_B), .hsync_n(VGA_HS), .vsync_n(VGA_VS));
endmodule
