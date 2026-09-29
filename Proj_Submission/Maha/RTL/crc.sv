import crc_pkg::*;
import crc_calc_pkg::*;

`include "crc_config.svh"

module crc (
  input logic clk,
  input logic rst_n,
  input i_flit_s i_flit,
  output o_flit_s o_flit
);

`ifdef NO_SPLIT_1024_CONFIG
logic [2:0] cycle_per_flit_counter;
logic [CRC_BITS_WIDTH -1 : 0] crc_state;

`elsif SPLIT_1024_CONFIG
logic [CRC_BITS_WIDTH -1 : 0] crc_state_0;
logic [CRC_BITS_WIDTH -1 : 0] crc_state_1;
`endif

// End of Packet delayed by 1 cycle
logic end_of_packet_d1;


`ifdef NO_SPLIT_1024_CONFIG
// Flag that asserts from the start_of_packet until the end_of_packet
logic packet_active;
logic packet_active_reg;  // To assert flag on the same cycle as SOP

// Flag that asserts from the start_of_packet until the end_of_packet
always_ff @(posedge clk or negedge rst_n)
begin
  if (!rst_n)
  begin
    packet_active_reg <= 1'b0;
  end

  else if (i_flit.start_of_packet)
  begin
    packet_active_reg <= 1'b1;
  end

  else if (end_of_packet_d1)
  begin
    packet_active_reg <= 1'b0;
  end
end

// Flag is asserted on the same cycle as SOP and held until EOP
assign packet_active = packet_active_reg || i_flit.start_of_packet;
`endif


// End of Packet delayed by 1 cycle
always_ff @(posedge clk or negedge rst_n)
begin
  if (!rst_n)
  begin
    end_of_packet_d1 <= 'b0;
  end

  else
  begin
    end_of_packet_d1 <= i_flit.end_of_packet;
  end
end



always_ff @(posedge clk or negedge rst_n)
begin
  if (!rst_n)
  begin
    o_flit <= 0;

    `ifdef NO_SPLIT_1024_CONFIG
    crc_state <= 0;
    cycle_per_flit_counter <= 0;
    `endif
  end

`ifdef NO_SPLIT_1024_CONFIG

  else if (i_flit.i_data_valid && packet_active)
  begin
    // Last chunk of the payload, process only the valid data bits without the reserved bits
    if (cycle_per_flit_counter == `NO_OF_CYCLES_PER_FLIT -1)
    begin
      o_flit.data_out [(0 + cycle_per_flit_counter*`INPUT_DATA_BUS_WIDTH) +: `INPUT_DATA_BUS_WIDTH - RESERVED_BITS_WIDTH] <= i_flit.data_in [(`INPUT_DATA_BUS_WIDTH - 1) - RESERVED_BITS_WIDTH : 0];
      o_flit.o_data_valid <= 1'b0;
      crc_state <= crc_calc (crc_state, i_flit.data_in, (FLIT_WIDTH - cycle_per_flit_counter*`INPUT_DATA_BUS_WIDTH - RESERVED_BITS_WIDTH)/8);

      cycle_per_flit_counter <= cycle_per_flit_counter + 1;
    end

    // All other data chunks, process the whole chunk
    else if ((cycle_per_flit_counter != `NO_OF_CYCLES_PER_FLIT) && (cycle_per_flit_counter != `NO_OF_CYCLES_PER_FLIT -1))
    begin
      o_flit.data_out [(0 + cycle_per_flit_counter*`INPUT_DATA_BUS_WIDTH) +: `INPUT_DATA_BUS_WIDTH] <= i_flit.data_in;
      o_flit.o_data_valid <= 1'b0;
      crc_state <= crc_calc (crc_state, i_flit.data_in, `INPUT_DATA_BUS_WIDTH/8);

      cycle_per_flit_counter <= cycle_per_flit_counter + 1;
    end

    // Extra assembly cycle -> construct data_out flit
    else if (cycle_per_flit_counter == `NO_OF_CYCLES_PER_FLIT)
    begin
      o_flit.data_out [TOTAL_DATA_WIDTH + CRC_BITS_WIDTH - 1 : TOTAL_DATA_WIDTH] <= crc_state;
      o_flit.data_out [FLIT_WIDTH - 1 : TOTAL_DATA_WIDTH + CRC_BITS_WIDTH] <= 'b0;
      o_flit.o_data_valid <= 1'b1;
      crc_state <= 0;

      cycle_per_flit_counter <= 0;
    end
  end

`elsif SPLIT_1024_CONFIG

  else if (i_flit.i_data_valid)
  begin
    // Extra assembly cycle -> calculate final crc_state and construct data_out flit
    if (end_of_packet_d1)
    begin
      o_flit.data_out [FLIT_WIDTH -1 : FLIT_WIDTH - RESERVED_BITS_WIDTH] <= {48'b0, (crc_calc (crc_state_0, 'b0, (`SPLIT_DATA_WIDTH - RESERVED_BITS_WIDTH)/8) ^ crc_state_1)};
      o_flit.o_data_valid <= 1'b1;
    end

    // First 1024-bit chunk
    else if (i_flit.start_of_packet)
    begin
      o_flit.data_out [`INPUT_DATA_BUS_WIDTH -1 : 0] <= i_flit.data_in;
      o_flit.o_data_valid <= 1'b0;
      crc_state_0 <= crc_calc ('b0,  i_flit.data_in [`SPLIT_DATA_WIDTH -1 : 0], `SPLIT_DATA_WIDTH/8);    // First 512 bits
      crc_state_1 <= crc_calc ('b0,  i_flit.data_in [`INPUT_DATA_BUS_WIDTH -1 : `SPLIT_DATA_WIDTH], `SPLIT_DATA_WIDTH/8);   // Second 512 bits
    end

    // Second 1024-bit chunk
    else if (i_flit.end_of_packet)
    begin
      o_flit.data_out [FLIT_WIDTH - RESERVED_BITS_WIDTH -1 : `INPUT_DATA_BUS_WIDTH] <= i_flit.data_in [`INPUT_DATA_BUS_WIDTH - RESERVED_BITS_WIDTH -1 : 0];
      o_flit.o_data_valid <= 1'b0;
      crc_state_0 <= crc_calc (crc_calc (crc_state_0, 'b0, `SPLIT_DATA_WIDTH/8), 'b0, `SPLIT_DATA_WIDTH/8) ^ crc_calc (crc_state_1, 'b0, `SPLIT_DATA_WIDTH/8) ^ crc_calc ('b0, i_flit.data_in [`SPLIT_DATA_WIDTH-1 : 0], `SPLIT_DATA_WIDTH/8);
      crc_state_1 <= crc_calc ('b0, i_flit.data_in [`INPUT_DATA_BUS_WIDTH-1 : `SPLIT_DATA_WIDTH], (`SPLIT_DATA_WIDTH - RESERVED_BITS_WIDTH)/8);
    end
  end

`endif

end

endmodule