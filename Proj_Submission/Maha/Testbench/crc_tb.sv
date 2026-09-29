`timescale 1ns/1ps

import crc_pkg::*;
import crc_golden_model_pkg::*;

`include "crc_config.svh"

module crc_tb;
logic clk;
logic rst_n;
i_flit_s i_flit;
o_flit_s o_flit;

// To collect data_in to send to reference model
logic [`NO_OF_CYCLES_PER_FLIT -1 : 0] [`INPUT_DATA_BUS_WIDTH -1 : 0] data_in_ref_model;
logic [TOTAL_DATA_WIDTH + CRC_BITS_WIDTH -1 : 0] expected_data_queue [$];

// Input data payload chunks
logic [`INPUT_DATA_BUS_WIDTH -1 : 0] payload_1, payload_2, payload_3, payload_4;


// Reporting
int pass_count, fail_count;


// Clock Generation
localparam CLK_PERIOD = 10;
always #(CLK_PERIOD/2) clk = ~clk;


// DUT Instantiation
crc dut (.*);


initial
begin
  initialize;

  assert_reset;


`ifdef CONFIG_1024
repeat (1000)
begin
  payload_1 = {
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom
  };

  payload_2 = {
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom
  };

  drive_1024_config (payload_1, payload_2);
end

`elsif CONFIG_512
repeat (1000)
begin
  payload_1 = {
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom
  };

  payload_2 = {
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom
  };

  payload_3 = {
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom
  };

  payload_4 = {
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom,
      $urandom, $urandom, $urandom, $urandom
  };

  drive_512_config (payload_1, payload_2, payload_3, payload_4);
end

`endif

repeat (10) @(posedge clk);

$display ("\nTotal Passed Tests = %0d/%0d\nTotal Failed Tests = %0d/%0d\n", pass_count, pass_count + fail_count, fail_count, pass_count + fail_count);

$stop;
end


always
begin
  @(posedge o_flit.o_data_valid);

  `ifdef CONFIG_1024
  check_1024_config();
  `elsif CONFIG_512
  check_512_config();
  `endif
end




task initialize;
clk = 0;
rst_n = 1;
i_flit = 0;
endtask


task assert_reset;
@(negedge clk);
rst_n = 0;

repeat (2) @(negedge clk);
rst_n = 1;
endtask


// Drive Flit in 1024 config mode over 2 cycles
task drive_1024_config;
input [`INPUT_DATA_BUS_WIDTH -1 : 0] first_payload, second_payload;

@(negedge clk);
i_flit.start_of_packet = 1;
i_flit.data_in = first_payload;
i_flit.i_data_valid = 1;
i_flit.end_of_packet = 0;

data_in_ref_model[0] = i_flit.data_in;

@(negedge clk);
i_flit.start_of_packet = 0;
i_flit.data_in = second_payload;
i_flit.i_data_valid = 1;
i_flit.end_of_packet = 1;

data_in_ref_model[1] = i_flit.data_in;

expected_data_queue.push_back(crc_golden_model(data_in_ref_model));
@(negedge clk);
i_flit.end_of_packet = 0;
endtask


// Check flit after adding CRC bits calculted for 1024 config mode
task check_1024_config;
logic [TOTAL_DATA_WIDTH + CRC_BITS_WIDTH -1 : 0] expected_data;

expected_data = expected_data_queue.pop_front;

if (o_flit.data_out [TOTAL_DATA_WIDTH + CRC_BITS_WIDTH -1 : 0] == expected_data)
begin
`ifdef CONFIG_1024
  `ifdef NO_SPLIT_1024_CONFIG
  $display ("\n[SUCCESS] 1024-configured Flit \n---Expected data_out--- = %512h \n---Actual data_out--- = %512h", expected_data, o_flit.data_out);
  `elsif SPLIT_DATA_WIDTH
  $display ("\n[SUCCESS] 1024-configured Flit (Split Configuration)\n---Expected data_out--- = %512h \n---Actual data_out--- = %512h", expected_data, o_flit.data_out);
  `endif
`endif

  pass_count ++;
end

else
begin
`ifdef CONFIG_1024
  `ifdef NO_SPLIT_1024_CONFIG
  $display ("\n[FAIL] 1024-configured Flit \n---Expected data_out--- = %512h \n---Actual data_out--- = %512h", expected_data, o_flit.data_out);
  `elsif SPLIT_DATA_WIDTH
  $display ("\n[FAIL] 1024-configured Flit (Split Configuration)\n---Expected data_out--- = %512h \n---Actual data_out--- = %512h", expected_data, o_flit.data_out);
  `endif
`endif

  fail_count ++;
end
endtask


// Drive Flit in 512 config mode over 4 cycles
task drive_512_config;
input [`INPUT_DATA_BUS_WIDTH -1 : 0] first_payload, second_payload, third_payload, fourth_payload;

@(negedge clk);
i_flit.start_of_packet = 1;
i_flit.data_in = first_payload;
i_flit.i_data_valid = 1;
i_flit.end_of_packet = 0;

data_in_ref_model[0] = i_flit.data_in;

@(negedge clk);
i_flit.start_of_packet = 0;
i_flit.data_in = second_payload;
i_flit.i_data_valid = 1;
i_flit.end_of_packet = 0;

data_in_ref_model[1] = i_flit.data_in;

@(negedge clk);
i_flit.start_of_packet = 0;
i_flit.data_in = third_payload;
i_flit.i_data_valid = 1;
i_flit.end_of_packet = 0;

data_in_ref_model[2] = i_flit.data_in;

@(negedge clk);
i_flit.start_of_packet = 0;
i_flit.data_in = fourth_payload;
i_flit.i_data_valid = 1;
i_flit.end_of_packet = 1;

data_in_ref_model[3] = i_flit.data_in;

expected_data_queue.push_back(crc_golden_model(data_in_ref_model));
@(negedge clk);
i_flit.end_of_packet = 0;
endtask


// Check flit after adding CRC bits calculted for 512 config mode
task check_512_config;
logic [TOTAL_DATA_WIDTH + CRC_BITS_WIDTH -1 : 0] expected_data;

expected_data = expected_data_queue.pop_front;

if (o_flit.data_out [TOTAL_DATA_WIDTH + CRC_BITS_WIDTH -1 : 0] == expected_data)
begin
  $display ("\n[SUCCESS] 512-configured Flit \n---Expected data_out--- = %512h \n---Actual data_out--- = %512h", expected_data, o_flit.data_out);
  pass_count ++;
end

else
begin
  $display ("\n[FAIL] 512-configured Flit \n---Expected data_out--- = %512h \n---Actual data_out--- = %512h", expected_data, o_flit.data_out);
  fail_count ++;
end
endtask

endmodule