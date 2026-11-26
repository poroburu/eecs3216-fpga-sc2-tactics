`timescale 1ns/1ps
import sc2fpga_pkg::*;

module tb_lanchester;
  logic clk = 0, rst = 1, eval = 0, regroup_en = 1;
  logic [4:0] n_f = 0, n_e = 0;
  logic [CW-1:0] f_x [MAX_UNITS], f_y [MAX_UNITS];
  logic [MAX_UNITS-1:0] f_squad = '0;

  logic [1:0] state_a, state_b;
  logic [11:0] p_a, p_b, p_ab, p_e;
  logic [CW-1:0] rally_ax, rally_ay, rally_bx, rally_by;
  logic together, done;

  always #10 clk = ~clk;

  lanchester_ctrl dut (.*);

  task automatic step_eval(
    input int na, input int ax, input int ay,
    input int nb, input int bx, input int by,
    input int ne, input logic en
  );
    regroup_en = en;
    n_f = 5'(na + nb);
    n_e = 5'(ne);
    f_squad = '0;
    for (int k = 0; k < MAX_UNITS; k++) begin
      if (k < na) begin
        f_x[k] = CW'(ax); f_y[k] = CW'(ay); f_squad[k] = 1'b0;
      end else if (k < na + nb) begin
        f_x[k] = CW'(bx); f_y[k] = CW'(by); f_squad[k] = 1'b1;
      end else begin
        f_x[k] = '0; f_y[k] = '0;
      end
    end
    @(posedge clk); eval = 1;
    @(posedge clk); eval = 0;
    wait (done);
    @(posedge clk);
  endtask

  task automatic check(input string name, input logic cond);
    if (!cond) begin
      $display("FAIL [%s]: stA=%0d stB=%0d pA=%0d pB=%0d pAB=%0d pE=%0d tog=%0d rA=(%0d,%0d)",
               name, state_a, state_b, p_a, p_b, p_ab, p_e, together, rally_ax, rally_ay);
      $fatal(1);
    end else begin
      $display("PASS [%s]: stA=%0d stB=%0d pA=%0d pB=%0d pAB=%0d pE=%0d tog=%0d",
               name, state_a, state_b, p_a, p_b, p_ab, p_e, together);
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    rst = 0;

    // 1) Two 5-Marine squads far apart (10 map units = 160 Q.4) vs 4 Roaches -> REGROUP (1)
    step_eval(5, 400, 400, 5, 560, 400, 4, 1);
    check("apart_weak_regroup", state_a == 1 && state_b == 1 && p_a == 25 && p_ab == 100 && p_e == 64 && !together && rally_ax == 560 && rally_bx == 400);

    // 2) They move within 2 map units (32 Q.4) -> combined 100 >= 64+8 -> ATTACK (0)
    step_eval(5, 464, 400, 5, 496, 400, 4, 1);
    check("together_reengage", state_a == 0 && state_b == 0 && together);

    // 3) Casualties drop them to 3+4=7 Marines (pAB=49 < 64) while together -> HOLD (2)
    step_eval(3, 464, 400, 4, 496, 400, 4, 1);
    check("depleted_hold", state_a == 2 && state_b == 2 && p_ab == 49 && together);

    // 4) Hysteresis check: 4+4=8 Marines (pAB=64 == pE=64, below 64+8=72) -> stays HOLD (2)
    step_eval(4, 464, 400, 4, 496, 400, 4, 1);
    check("hysteresis_no_flicker", state_a == 2 && state_b == 2);

    // 5) One Roach dies (ne=3 -> pE=36; 64 >= 36+8=44) -> re-enters ATTACK (0)
    step_eval(4, 464, 400, 4, 496, 400, 3, 1);
    check("enemy_weakened_attack", state_a == 0 && state_b == 0);

    // 6) SW1=0 disables regrouping even when weak and apart -> ATTACK (0)
    step_eval(5, 400, 400, 5, 560, 400, 4, 0);
    check("sw1_off_bypass", state_a == 0 && state_b == 0);

    $display("ALL LANCHESTER TESTS PASSED");
    $finish;
  end
endmodule
