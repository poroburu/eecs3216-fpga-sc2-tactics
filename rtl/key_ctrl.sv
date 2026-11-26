// KEY0/KEY1 front end: synchronize, debounce, and decode.
//
//   KEY0 released  -> ev pulse, ev_op = 0 (add one unit)
//   KEY1 released  -> ev pulse, ev_op = 1 (remove one unit)
//   both held for RESET_HOLD_CLKS -> reset_req (one 16-cycle pulse); a press that overlapped the
//   other key (a chord) never produces an add/remove event, so the reset gesture edits nothing.
module key_ctrl #(
  parameter int DEBOUNCE_CLKS   = 1_000_000,   // 20 ms at 50 MHz
  parameter int RESET_HOLD_CLKS = 50_000_000   // 1 s at 50 MHz
) (
  input  logic       clk,
  input  logic       rst,
  input  logic [1:0] key_n,      // active-low push buttons
  output logic       reset_req,
  output logic       ev,         // 1-cycle pulse
  output logic       ev_op       // 0 = add (KEY0), 1 = remove (KEY1)
);
  localparam int DBW = $clog2(DEBOUNCE_CLKS + 1);
  localparam int HW  = $clog2(RESET_HOLD_CLKS + 1);

  logic [1:0] k_m, k_s, pressed, prev;
  logic [DBW-1:0] db_cnt [2];
  logic [HW-1:0]  hold_cnt;
  logic           chord;
  logic [3:0]     rst_stretch;

  assign reset_req = (rst_stretch != 0);

  always_ff @(posedge clk) begin
    k_m <= ~key_n; k_s <= k_m;
    if (rst) begin
      pressed <= '0; prev <= '0; db_cnt[0] <= '0; db_cnt[1] <= '0;
      hold_cnt <= '0; chord <= 1'b0; rst_stretch <= '0; ev <= 1'b0; ev_op <= 1'b0;
    end else begin
      ev <= 1'b0;
      for (int i = 0; i < 2; i++) begin
        if (k_s[i] == pressed[i]) db_cnt[i] <= '0;
        else if (db_cnt[i] == DBW'(DEBOUNCE_CLKS)) begin pressed[i] <= k_s[i]; db_cnt[i] <= '0; end
        else db_cnt[i] <= db_cnt[i] + 1'b1;
      end
      prev <= pressed;

      if (pressed == 2'b11) begin
        chord <= 1'b1;
        if (hold_cnt == HW'(RESET_HOLD_CLKS)) rst_stretch <= 4'hF;
        if (hold_cnt != {HW{1'b1}}) hold_cnt <= hold_cnt + 1'b1;
      end else begin
        hold_cnt <= '0;
        if (pressed == 2'b00) chord <= 1'b0;
      end
      if (rst_stretch != 0) rst_stretch <= rst_stretch - 4'd1;

      if (!chord && pressed != 2'b11) begin
        if (prev[0] && !pressed[0])      begin ev <= 1'b1; ev_op <= 1'b0; end
        else if (prev[1] && !pressed[1]) begin ev <= 1'b1; ev_op <= 1'b1; end
      end
    end
  end
endmodule
