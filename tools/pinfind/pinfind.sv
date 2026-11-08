// Pin finder: discovers which DE10-Lite header pins the USB-UART adapter is wired to.
// Safe by default: every header pin is an input with a weak pull-up. Nothing is driven
// until the host selects ONE pin over JTAG (In-System Sources and Probes).
//   probe  [51:0]  sticky "this pin was seen low"  (PC transmitting -> its TX line toggles)
//   probe [103:52] current pin level
//   source [7]     clear sticky bits
//   source [6]     drive enable, source[5:0] pin index 0..51 (0..35 = GPIO, 36..51 = ARDUINO_IO)
// When enabled, the selected pin repeatedly transmits one 115200 8-N-1 byte = its index.
module pinfind (input logic MAX10_CLK1_50, input logic [1:0] KEY,
                inout wire [35:0] GPIO, inout wire [15:0] ARDUINO_IO, output logic [9:0] LEDR);
  wire [51:0] pins_in = {ARDUINO_IO, GPIO};
  logic [51:0] s1, s2, seen;
  logic [7:0]  src;
  always_ff @(posedge MAX10_CLK1_50) begin
    s1 <= pins_in; s2 <= s1;
    if (!KEY[0] || src[7]) seen <= '0; else seen <= seen | ~s2;
  end
  altsource_probe #(.sld_auto_instance_index("YES"), .sld_instance_index(0), .instance_id("PINF"),
    .probe_width(104), .source_width(8), .source_initial_value("0"), .enable_metastability("YES"),
    .lpm_type("altsource_probe")) issp (.probe({s2, seen}), .source(src), .source_clk(MAX10_CLK1_50), .source_ena(1'b1));
  // repeating UART byte generator
  localparam int CPB = 434;
  logic [8:0] cnt; logic [3:0] bitn; logic [9:0] shreg; logic txd;
  always_ff @(posedge MAX10_CLK1_50)
    if (cnt != 0) cnt <= cnt - 1'd1;
    else begin
      cnt <= CPB[8:0] - 1'd1;
      if (bitn == 4'd11) begin bitn <= 0; shreg <= {1'b1, 2'b00, src[5:0], 1'b0}; txd <= 1'b1; end // idle bit between bytes
      else begin txd <= shreg[0]; shreg <= {1'b1, shreg[9:1]}; bitn <= bitn + 1'd1; end
    end
  genvar k;
  generate for (k = 0; k < 52; k++) begin : drv
    wire en = src[6] && (src[5:0] == k);
    if (k < 36) assign GPIO[k] = en ? txd : 1'bz;
    else        assign ARDUINO_IO[k-36] = en ? txd : 1'bz;
  end endgenerate
  assign LEDR = {src[6], 3'b0, src[5:0]};
endmodule
