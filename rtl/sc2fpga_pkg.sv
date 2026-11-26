// Shared constants for the SC2 target-selection & Lanchester tactical coprocessor.
package sc2fpga_pkg;
  localparam int MAX_UNITS = 16;           // per side
  localparam int CW        = 11;           // coordinate width: unsigned Q7.4, 0..2047 (1/16 map unit)
  localparam int D2W       = 23;           // squared-distance width: 2*(2047^2) < 2^23
  localparam int KEYW      = 1 + 8 + D2W + 4; // {out_of_range, hp_term, d2, j} = 36 bits

  localparam logic [7:0] REQ_SYNC    = 8'hA5; // V1: single-squad legacy request
  localparam logic [7:0] RSP_SYNC    = 8'h5A; // V1: single-squad legacy reply
  localparam logic [7:0] REQ_SYNC_V2 = 8'hA6; // V2: two-squad Lanchester request
  localparam logic [7:0] RSP_SYNC_V2 = 8'h5B; // V2: two-squad Lanchester reply
  localparam logic [7:0] NO_TARGET   = 8'hFF;

  // Per-squad tactical states
  localparam logic [1:0] SQ_ATTACK   = 2'd0;
  localparam logic [1:0] SQ_REGROUP  = 2'd1;
  localparam logic [1:0] SQ_FALLBACK = 2'd2;   // retreat away from the enemy centroid

  // Reply status codes
  localparam logic [7:0] ST_OK           = 8'd0;
  localparam logic [7:0] ST_BAD_CHECKSUM = 8'd1;
  localparam logic [7:0] ST_BAD_COUNT    = 8'd2;
  localparam logic [7:0] ST_TIMEOUT      = 8'd3;
  localparam logic [7:0] ST_BAD_RANGE    = 8'd4;
endpackage
