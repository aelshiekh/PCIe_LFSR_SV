`include "crc_config.svh"

package crc_calc_pkg;

  localparam logic [8:0] CRC_PRIM_POLY = 9'h12B; // x^8+x^5+x^3+x+1

  localparam logic [7:0] CRC_G0 = 8'h69; // alpha^36
  localparam logic [7:0] CRC_G1 = 8'h4D; // alpha^199
  localparam logic [7:0] CRC_G2 = 8'h41; // alpha^134
  localparam logic [7:0] CRC_G3 = 8'h33; // alpha^195
  localparam logic [7:0] CRC_G4 = 8'hD5; // alpha^172
  localparam logic [7:0] CRC_G5 = 8'hFE; // alpha^186
  localparam logic [7:0] CRC_G6 = 8'h68; // alpha^116
  localparam logic [7:0] CRC_G7 = 8'hD5; // alpha^172

  // GF(2^8) multiply, reduction poly x^8+x^5+x^3+x+1. Pure combinational.
  function automatic logic [7:0] gf256_mult(input logic [7:0] a, input logic [7:0] b);
    logic [14:0] r;
    logic [14:0] a_ext;
    int i;
    r = 15'd0;
    a_ext = {7'd0, a};
    for (i = 0; i < 8; i++) begin
      if (b[i]) r ^= (a_ext << i);
    end
    for (i = 14; i >= 8; i--) begin
      if (r[i]) r ^= (({6'd0, CRC_PRIM_POLY}) << (i-8));
    end
    gf256_mult = r[7:0];
  endfunction

  // Advances the 8-byte state by one input byte.
  // state packed as {B7,B6,B5,B4,B3,B2,B1,B0}, B0 = CRC0 in the LSB byte.
  function automatic logic [63:0] crc_byte_step(input logic [63:0] state_in, input logic [7:0] data_byte);
    logic [7:0] b0,b1,b2,b3,b4,b5,b6,b7;
    logic [7:0] fb;
    b0 = state_in[7:0];   b1 = state_in[15:8];  b2 = state_in[23:16]; b3 = state_in[31:24];
    b4 = state_in[39:32]; b5 = state_in[47:40]; b6 = state_in[55:48]; b7 = state_in[63:56];
    fb = data_byte ^ b7;
    crc_byte_step = { b6 ^ gf256_mult(fb, CRC_G7),   // new B7
                       b5 ^ gf256_mult(fb, CRC_G6),   // new B6
                       b4 ^ gf256_mult(fb, CRC_G5),   // new B5
                       b3 ^ gf256_mult(fb, CRC_G4),   // new B4
                       b2 ^ gf256_mult(fb, CRC_G3),   // new B3
                       b1 ^ gf256_mult(fb, CRC_G2),   // new B2
                       b0 ^ gf256_mult(fb, CRC_G1),   // new B1
                             gf256_mult(fb, CRC_G0)   // new B0
                     };
  endfunction


// Calculate CRC over all valid payload bytes
function automatic logic [63:0] crc_calc(
    input logic [63:0] state_in,

  `ifdef NO_SPLIT_1024_CONFIG
    input logic [`INPUT_DATA_BUS_WIDTH-1:0] data,
  `elsif SPLIT_1024_CONFIG
    input logic [`SPLIT_DATA_WIDTH-1:0] data,
  `endif

    input int num_valid_bytes
);
  logic [63:0] state;
  state = state_in;
  for (int k = 0; k < `INPUT_DATA_BUS_WIDTH/8; k++)
  begin
    if (k < num_valid_bytes)
      state = crc_byte_step(state, data[k*8 +: 8]);
    // else: state simply isn't updated this iteration -> effectively "held"
  end
  crc_calc = state;
endfunction


endpackage : crc_calc_pkg
