`include "crc_config.svh"

// clk/rst_n are always in the port list. They are used by the 
// pipelined version and unused by the standard combinational build.

module crc_calculator
    import crc_pkg::*;
(
    input  logic                          clk,
    input  logic                          rst_n,
    input  pkt_t                          pkt_in,
    input  crc_t                          crc_in,
    input  logic [$clog2(NUM_CHUNKS)-1:0] chunk_count,
    output crc_t                          crc_out
);

    function automatic crc_t crc_calculate (
        input pkt_t pkt,
        input int   off,
        input int   j_lo,
        input int   j_hi
    );
        crc_t crc = '0;
        for (int i = 0; i < 8; i++)
            for (int j = j_lo; j < j_hi; j++)
                if ((j + off) < PAYLOAD_BYTES) // Skip the 14 zero bytes. 
                // Alternative: keep the matrix at 2048 rows, with rows 0–111 set to zero,
                // allowing synthesis to optimize away the resulting logic.
                // Probably doesn't matter in this case, due to the usage of generate loops.
                    for (int k = 0; k < 8; k++)
                        crc[i] ^= {8{pkt.data[j][k]}} &
                                  crc_matrix[MATRIX_ROWS-1 - (k + 8*(j + off))][7-i];
        return crc;
    endfunction

`ifdef CRC_USE_SPLIT

    crc_t lo_per_chunk [NUM_CHUNKS];
    crc_t hi_per_chunk [NUM_CHUNKS];

    for (genvar c = 0; c < NUM_CHUNKS; c++) begin : gen_chunk
        localparam int OFFSET = c << $clog2(DATA_BYTES);
        assign lo_per_chunk[c] = crc_calculate(pkt_in, OFFSET, 0, DATA_BYTES/2);
        assign hi_per_chunk[c] = crc_calculate(pkt_in, OFFSET, DATA_BYTES/2, DATA_BYTES);
    end

    crc_t crc_1, crc_2;

    assign crc_out = crc_1 ^ crc_2 ^ crc_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_1 <= '0;
            crc_2 <= '0;
        end else if (pkt_in.valid) begin
            crc_1 <= lo_per_chunk[chunk_count];
            crc_2 <= hi_per_chunk[chunk_count];
        end
    end

`else

    crc_t contrib_per_chunk [NUM_CHUNKS];

    for (genvar c = 0; c < NUM_CHUNKS; c++) begin : gen_chunk
        localparam int OFFSET = c << $clog2(DATA_BYTES);
        assign contrib_per_chunk[c] = crc_calculate(pkt_in, OFFSET, 0, DATA_BYTES);
    end

    assign crc_out = pkt_in.valid ? (crc_in ^ contrib_per_chunk[chunk_count]) : crc_in;

`endif

endmodule