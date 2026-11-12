// 7-segment decoder for the DE10-Lite (segments active-low, seg[7] = decimal point).
// code 0..15 = hex digit; 16 = blank; 17 = '-'.
module hex7seg (input logic [4:0] code, output logic [7:0] seg);
  logic [6:0] on;   // active-high {g,f,e,d,c,b,a}
  always_comb begin
    case (code)
      5'd0:  on = 7'b0111111;  5'd1:  on = 7'b0000110;  5'd2:  on = 7'b1011011;  5'd3:  on = 7'b1001111;
      5'd4:  on = 7'b1100110;  5'd5:  on = 7'b1101101;  5'd6:  on = 7'b1111101;  5'd7:  on = 7'b0000111;
      5'd8:  on = 7'b1111111;  5'd9:  on = 7'b1101111;  5'd10: on = 7'b1110111;  5'd11: on = 7'b1111100;
      5'd12: on = 7'b0111001;  5'd13: on = 7'b1011110;  5'd14: on = 7'b1111001;  5'd15: on = 7'b1110001;
      5'd17: on = 7'b1000000;
      default: on = 7'b0000000;
    endcase
    seg = {1'b1, ~on};
  end
endmodule
