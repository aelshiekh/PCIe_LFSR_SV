`include "crc_config.svh"

package crc_pkg;

parameter FLIT_WIDTH = 2048;
parameter TOTAL_DATA_WIDTH = 1936;
parameter RESERVED_BITS_WIDTH = FLIT_WIDTH - TOTAL_DATA_WIDTH;
parameter CRC_BITS_WIDTH = 64;

// Input Flit Struct (w/o CRC bits)
typedef struct packed {
  logic start_of_packet;
  logic i_data_valid;
  logic [`INPUT_DATA_BUS_WIDTH-1 : 0] data_in;
  logic end_of_packet;
} i_flit_s;


// Output Flit Struct (w/ CRC bits)
typedef struct packed {
  logic o_data_valid;
  logic [FLIT_WIDTH-1 : 0] data_out;
} o_flit_s;


endpackage