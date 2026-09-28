`include "crc_config.svh"
import crc_pkg::*;

// -----------------------------------------------------------------------------
// tb_pci_crc
//
// The one thing that DOES differ by config is pkt_in -> pkt_out latency:
//   non-pipelined : 1 register  (pkt_out driven directly from pkt_in)          -> DUT_LATENCY = 1
//   pipelined     : 2 registers (pkt_out driven from pkt_in_reg, which is
//               itself one register removed from pkt_in)                       -> DUT_LATENCY = 2
// DUT_LATENCY-1 extra `@(negedge clk)` cycles are waited before sampling
// pkt_out, so the same checker is correct for every config without knowing
// anything else about the internals.
// -----------------------------------------------------------------------------
module tb_pci_crc;

`ifdef CRC_USE_SPLIT
    localparam int DUT_LATENCY = 2;
`else
    localparam int DUT_LATENCY = 1;
`endif

    int success_ctr, error_ctr;

    // Number of comparison processes that are still running.
    int pending_checks;

    logic [255:0][7:0] random_data;

    logic [255:0][7:0] ref_data_in;
    logic [255:0][7:0] ref_data_out;

    // ---------------------------------------------------------
    // DUT
    // ---------------------------------------------------------
    logic clk, rst_n;
    pkt_t dut_pkt_in, dut_pkt_out;

    crc_ref Ref (.data_in(ref_data_in), .data_out(ref_data_out));
    crc_dut DUT (.clk(clk), .rst_n(rst_n), .pkt_in(dut_pkt_in), .pkt_out(dut_pkt_out));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    
    task automatic assert_reset();
        rst_n          = 1'b0;
        success_ctr    = 0;
        error_ctr      = 0;
        pending_checks = 0;

        ref_data_in = '0;
        dut_pkt_in  = '0;

        @(negedge clk);

        rst_n = 1'b1;
    endtask

    
    task automatic randomize_pkt();
        // First 242 bytes contain packet data
        for (int i = 0; i < 242; i++)
            random_data[i] = $urandom_range(0, 255);
        // Last 14 bytes are zero (CRC + ECC)
        for (int i = 242; i < 256; i++)
            random_data[i] = 8'h00;
    endtask

    task automatic drive_ref();
        ref_data_in = random_data;
    endtask

    // Bubbles are used to simulate gaps between valid chunks.
    task automatic drive_pkt_struct(bit inject_bubbles = 0, int max_bubbles = 3);
        int byte_idx;
        int bubbles;

        for (int i = 0; i < NUM_CHUNKS; i++) begin
            bubbles = 0;
            if (inject_bubbles)
                bubbles = $urandom_range(1, max_bubbles);

            repeat (bubbles) begin
                dut_pkt_in = '0; // valid, sop, eop and data are all zeroes.
                @(negedge clk);
            end

            for (int j = 0; j < DATA_BYTES; j++) begin
                byte_idx = i * DATA_BYTES + j;
                dut_pkt_in.data[j] = random_data[byte_idx];
            end
            dut_pkt_in.valid = 1'b1;
            dut_pkt_in.sop   = (i == 0);
            dut_pkt_in.eop   = (i == NUM_CHUNKS - 1);

            @(negedge clk); // one chunk per cycle
        end
    endtask

    
    task automatic drive_dut_idle();
        dut_pkt_in = '0; // valid, sop, eop and data are all zeroes.
        @(negedge clk);
    endtask

    task automatic compare(
        input logic [7:0][7:0]   expected_crc,
        input logic [255:0][7:0] expected_data,
        input string             test_name = ""
    );
        logic [7:0][7:0] dut_crc;

        repeat (DUT_LATENCY - 1) @(negedge clk);

        dut_crc = dut_pkt_out.data[DATA_BYTES-7 : DATA_BYTES-14];

        if (dut_crc == expected_crc) begin
            success_ctr++;
        end else begin
            error_ctr++;
            $display("[%0t] MISMATCH (%s)", $time, test_name);
            $display("  input   = %h", expected_data);
            $display("  got crc = %h", dut_crc);
            $display("  exp crc = %h", expected_crc);
        end

        pending_checks--;
    endtask


    task automatic run_pattern(logic [255:0][7:0] pattern,
                                bit inject_bubbles = 0,
                                string name        = "pattern");

        logic [7:0][7:0]   expected_crc;
        logic [255:0][7:0] expected_data;

        random_data = pattern;

        fork
            drive_ref();
            drive_pkt_struct(inject_bubbles);
        join

        // Capture expected result before the next packet can touch
        // random_data / ref_data_out.
        expected_data = random_data;
        expected_crc  = ref_data_out[249:242];

        // Launch the checker asynchronously: it waits, but the next
        // packet's stimulus does not have to.
        pending_checks++;
        fork
            automatic logic [7:0][7:0]   crc_copy  = expected_crc;
            automatic logic [255:0][7:0] data_copy = expected_data;
            compare(crc_copy, data_copy, name);
        join_none
    endtask

    // ---------------------------------------------------------
    // Random test
    // ---------------------------------------------------------
    task automatic random_test(bit inject_bubbles = 0);
        logic [7:0][7:0]   expected_crc;
        logic [255:0][7:0] expected_data;

        randomize_pkt();

        fork
            drive_ref();
            drive_pkt_struct(inject_bubbles);
        join

        expected_data = random_data;
        expected_crc  = ref_data_out[249:242];

        pending_checks++;
        fork
            automatic logic [7:0][7:0]   crc_copy  = expected_crc;
            automatic logic [255:0][7:0] data_copy = expected_data;
            compare(crc_copy, data_copy, inject_bubbles ? "random+bubbles" : "random");
        join_none
    endtask

    initial begin
        assert_reset();

        $display("");
        $display("========================================");
        $display("TEST 1: Back-to-back random packets");
        $display("========================================");
        repeat (100) random_test();

        $display("");
        $display("========================================");
        $display("TEST 2: Random packets with idle gap");
        $display("========================================");
        repeat (10) begin
            drive_dut_idle();
            random_test();
        end

        $display("");
        $display("========================================");
        $display("TEST 3: All zeros");
        $display("========================================");
        run_pattern('0, 0, "all_zeros");

        $display("");
        $display("========================================");
        $display("TEST 4: All ones");
        $display("========================================");
        run_pattern('1, 0, "all_ones");

        $display("");
        $display("========================================");
        $display("TEST 5: Random packets with bubbles");
        $display("========================================");
        repeat (20) random_test(1);

        // Wait for every checker to finish before scoring.
        wait (pending_checks == 0);

        $display("");
        $display("========================================");
        $display("FINAL RESULTS");
        $display("========================================");
        $display("Success Counter = %0d", success_ctr);
        $display("Error Counter   = %0d", error_ctr);
        $display("========================================");

        $finish;
    end

endmodule