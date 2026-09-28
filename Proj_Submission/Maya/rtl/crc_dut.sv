`include "crc_config.svh"
import crc_pkg::*;

// Only the `+define`s passed to vlog change which branch below gets compiled.

module crc_dut (
    input logic clk, rst_n,
    input pkt_t pkt_in,
    output pkt_t pkt_out
);

    crc_t crc_in, crc_out;
    logic [$clog2(NUM_CHUNKS)-1:0] chunk_count;

    crc_calculator crc_calc (
        .clk        (clk),
        .rst_n      (rst_n),
        .pkt_in     (pkt_in),
        .crc_in     (crc_in),
        .chunk_count(chunk_count),
        .crc_out    (crc_out)
    );

    state_t cs, ns;

    // Next State Logic
    always_comb begin
        ns = cs;
        if (pkt_in.valid) begin
            case (cs)
                IDLE:
                    if (pkt_in.sop) begin
                        ns = BUSY;
                    end
                BUSY:
                    if (pkt_in.eop) begin
                        ns = IDLE;
                    end
                default: ns = IDLE;
            endcase
        end
    end

    // Current State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= IDLE;
        end else begin
            cs <= ns;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chunk_count <= '0;
        end else if (pkt_in.valid) begin
            if (pkt_in.eop)
                chunk_count <= '0; // Normally returns to 0 at the end of each packet; explicit reset also prevents framing errors from propagating to the next packet
            else
                chunk_count <= chunk_count + 1'b1;
        end
    end

`ifdef CRC_USE_SPLIT

    // ---------------------------------------------------------------------
    // Pipelined
    // -------------------------------------------------------------------
    
    // The CRC output is delayed by one cycle, so the output packet must be
    // delayed as well. Therefore, the state and input packet are registered.
    state_t cs_reg;
    pkt_t   pkt_in_reg;

    // Delayed Signals
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_reg     <= IDLE;
            pkt_in_reg <= '0;
        end else begin
            cs_reg     <= cs;
            pkt_in_reg <= pkt_in;
        end
    end

    // Output Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_out <= '0;
            crc_in  <= CRC_INIT;
        end else begin
            pkt_out.valid <= pkt_in_reg.valid;
            pkt_out.sop   <= pkt_in_reg.sop && pkt_in_reg.valid;
            pkt_out.eop   <= pkt_in_reg.eop && pkt_in_reg.valid;

            if (pkt_in_reg.valid) begin
                case (cs_reg)
                    IDLE:
                        if (pkt_in_reg.sop)
                            pkt_out.data <= pkt_in_reg.data;
                    BUSY:
                        if (pkt_in_reg.eop)
                            pkt_out.data <= {48'b0, crc_out, pkt_in_reg.data[DATA_BYTES-15:0]};
                        else
                            pkt_out.data <= pkt_in_reg.data;
                endcase
            end

            if (pkt_in.valid) begin
                case (cs)
                    IDLE:
                        if (pkt_in.sop)
                            crc_in <= CRC_INIT;
                    BUSY:
                        crc_in <= crc_out;
                endcase
            end
        end
    end

`else

    // ---------------------------------------------------------------------
    // Standard
    // ---------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_out     <= 0;
            crc_in      <= CRC_INIT;
        end else begin
            pkt_out.valid <= pkt_in.valid;
            pkt_out.sop   <= pkt_in.sop && pkt_in.valid;
            pkt_out.eop   <= pkt_in.eop && pkt_in.valid;

            if (pkt_in.valid) begin
                case (cs)
                    IDLE:
                        if (pkt_in.sop) begin
                            crc_in       <= crc_out;
                            pkt_out.data <= pkt_in.data;
                        end
                    BUSY:
                        if (pkt_in.eop) begin
                            crc_in       <= CRC_INIT;
                            pkt_out.data <= {48'b0, crc_out, pkt_in.data[DATA_BYTES-15:0]};
                        end else begin
                            crc_in       <= crc_out;
                            pkt_out.data <= pkt_in.data;
                        end
                endcase
            end
        end
    end

`endif

endmodule