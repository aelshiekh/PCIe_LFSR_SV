// =============================================================================
// UCIe Link Training State Machine (LTSM) — Reference Skeleton
// =============================================================================
// SCOPE / DISCLAIMER:
//   This is a structural skeleton meant to anchor discussion and iteration,
//   NOT a spec-certified, tapeout-ready implementation. Items marked
//   "IMPL-DEFINED" or "SPEC-CHECK" need to be pinned down against the exact
//   UCIe spec revision (1.0/1.1/2.0) you're targeting and your PHY vendor's
//   analog characteristics. Timeout constants below are placeholders.
//
// STRUCTURE:
//   - Top-level LTSM (mainband-facing) states
//   - Sideband state machine runs semi-independently, gates progression
//     through rendezvous points (marked SB_SYNC below)
//   - MBINIT and MBTRAIN are expanded into sub-states since that's where
//     most real complexity lives
//
// SB_MGMT_UP HANDLING (added):
//   A 1->0 transition on sb_mgmt_up is a global override on top of normal
//   state progression:
//     - In S_SBINIT: drop straight to S_TRAINERROR -> S_RESET (sideband
//       management link is already down, so no handshake is attempted).
//     - In S_MBINIT: drop to S_TRAINERROR, but hold there until a
//       TRAINERROR handshake with the partner completes, THEN -> S_RESET.
//   trainerror_handshake_done is a placeholder input representing the
//   result of that handshake exchange; a real design needs a small SB
//   FSM for it (structurally similar to the SBINIT pattern/message FSM),
//   which isn't included in this file.
// =============================================================================

module ucie_ltsm #(
    parameter int NUM_LANES        = 32,   // IMPL-DEFINED: module width
    parameter int TIMEOUT_SBINIT   = 32'd100_001,  // IMPL-DEFINED placeholder
    parameter int TIMEOUT_MBINIT   = 32'd200_000,  // IMPL-DEFINED placeholder
    parameter int TIMEOUT_MBTRAIN  = 32'd500_000,  // IMPL-DEFINED placeholder
    parameter int MAX_RETRAIN_CNT  = 4             // IMPL-DEFINED placeholder
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Sideband management-link status. A 1->0 transition on this flag is a
    // global override: while in SBINIT it forces an immediate drop to
    // TRAINERROR; while in MBINIT it forces a TRAINERROR handshake before
    // dropping. See sb_mgmt_up_fell / trainerror_needs_handshake below.
    input  logic                   sb_mgmt_up,
    input  logic                   trainerror_handshake_done, // IMPL-DEFINED: from a small
                                                               // SB handshake FSM, not shown here

    // Sideband interface (simplified — real design needs a full SB packet layer)
    input  logic                   sb_msg_valid,
    input  logic [7:0]             sb_msg_type,      // SPEC-CHECK: encode per SB message opcode table
    output logic                   sb_msg_send,
    output logic [7:0]             sb_msg_type_out,

    // Mainband status aggregated from per-lane PHY logic
    input  logic [NUM_LANES-1:0]   lane_valid_pattern_detected,
    input  logic [NUM_LANES-1:0]   lane_calibration_done,
    input  logic [NUM_LANES-1:0]   lane_repair_needed,      // IMPL-DEFINED threshold logic upstream
    input  logic                   clock_pattern_locked,

    output logic [3:0]             ltsm_state_top,
    output logic [3:0]             mbinit_substate,
    output logic [3:0]             mbtrain_substate,
    output logic                   link_active,
    output logic                   link_error
);

    // -------------------------------------------------------------------
    // Top-level states (SPEC-CHECK names/order against target UCIe rev)
    // -------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_RESET       = 4'h0,
        S_SBINIT      = 4'h1,   // Sideband init: clock detect, SB training pattern exchange
        S_PARAM       = 4'h2,   // Parameter exchange over sideband (widths, speed, features)
        S_MBINIT      = 4'h3,   // Mainband init: expanded below
        S_MBTRAIN     = 4'h4,   // Mainband training: expanded below
        S_LINKINIT    = 4'h5,   // Final handshake before ACTIVE
        S_ACTIVE      = 4'h6,
        S_L1          = 4'h7,   // Low-power state, fast exit
        S_L2          = 4'h8,   // Low-power state, full retrain on exit
        S_PHYRETRAIN  = 4'h9,   // In-place retrain without dropping to RESET
        S_TRAINERROR  = 4'hA,
        S_DISABLED    = 4'hB
    } ltsm_state_e;

    // -------------------------------------------------------------------
    // MBINIT sub-states (SPEC-CHECK: exact sub-state set/names vary by rev)
    // -------------------------------------------------------------------
    typedef enum logic [3:0] {
        MBI_IDLE          = 4'h0,
        MBI_CLK_VALID     = 4'h1,  // detect valid clock on mainband
        MBI_VALID_PATTERN = 4'h2,  // per-lane valid-pattern detection
        MBI_LANE_REVERSAL = 4'h3,  // detect + correct lane reversal (IMPL-DEFINED alg detail)
        MBI_REPAIR        = 4'h4,  // map out / repair failed lanes if repair lanes present
        MBI_SPEED_ID      = 4'h5,  // speed identification handshake
        MBI_DONE          = 4'h6
    } mbinit_substate_e;

    // -------------------------------------------------------------------
    // MBTRAIN sub-states
    // -------------------------------------------------------------------
    typedef enum logic [3:0] {
        MBT_IDLE        = 4'h0,
        MBT_CAL         = 4'h1,  // per-lane analog calibration (IMPL-DEFINED: vendor PHY specific)
        MBT_VALID_PAT2  = 4'h2,  // second valid-pattern check at trained speed
        MBT_EYE_CHECK   = 4'h3,  // margin/eye check — IMPL-DEFINED thresholds
        MBT_DESKEW      = 4'h4,  // lane-to-lane deskew
        MBT_LINK_TEST   = 4'h5,  // pattern-based BER-style link test
        MBT_DONE        = 4'h6
    } mbtrain_substate_e;

    ltsm_state_e        state, next_state;
    mbinit_substate_e   mbi_sub, mbi_sub_next;
    mbtrain_substate_e  mbt_sub, mbt_sub_next;

    logic [31:0] timeout_cnt;
    logic [7:0]  retrain_cnt;

    // =====================================================================
    // SB_MGMT_UP monitor
    // Falling-edge detect, plus a latch recording whether the current
    // TRAINERROR entry needs to run a handshake before RESET (MBINIT case)
    // or can drop straight through (SBINIT case, sideband already down).
    // =====================================================================
    logic sb_mgmt_up_d;
    logic sb_mgmt_up_fell;
    logic trainerror_needs_handshake;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sb_mgmt_up_d <= 1'b1; // SPEC-CHECK: reset-time assumed value
        else        sb_mgmt_up_d <= sb_mgmt_up;
    end
    assign sb_mgmt_up_fell = sb_mgmt_up_d & ~sb_mgmt_up;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            trainerror_needs_handshake <= 1'b0;
        else if (sb_mgmt_up_fell && state == S_MBINIT)
            trainerror_needs_handshake <= 1'b1;
        else if (state == S_RESET)
            trainerror_needs_handshake <= 1'b0; // cleared once fully reset
    end

    // =====================================================================
    // Top-level state register
    // =====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_RESET;
            timeout_cnt <= '0;
            retrain_cnt <= '0;
        end else begin
            state <= next_state;
            if (state != next_state)
                timeout_cnt <= '0;
            else
                timeout_cnt <= timeout_cnt + 1;
        end
    end

    // =====================================================================
    // Top-level next-state logic
    // NOTE: Every "timeout_cnt > TIMEOUT_X" branch is a placeholder for
    // real timeout handling — SPEC-CHECK exact values per state.
    // =====================================================================
    always_comb begin
        next_state = state;

        // Global override: an SB_MGMT_UP drop takes priority over whatever
        // SBINIT/MBINIT were otherwise doing. SPEC-CHECK: the spec only
        // calls this out explicitly for these two states -- other states
        // may have their own (unhandled here) SB_MGMT_UP rules.
        if (sb_mgmt_up_fell && (state == S_SBINIT || state == S_MBINIT)) begin
            next_state = S_TRAINERROR;
        end else

        unique case (state)

            S_RESET: begin
                // Exit reset once reset de-asserted and reference clock stable
                next_state = S_SBINIT;
            end

            S_SBINIT: begin
                // SB_SYNC point: both sides must exchange SBINIT.done via sideband
                if (sb_msg_valid && sb_msg_type == 8'h01 /*SPEC-CHECK opcode*/)
                    next_state = S_PARAM;
                else if (timeout_cnt > TIMEOUT_SBINIT)
                    next_state = S_TRAINERROR;
            end

            S_PARAM: begin
                // Parameter exchange: width degrade negotiation, module IDs, etc.
                if (sb_msg_valid && sb_msg_type == 8'h02 /*SPEC-CHECK opcode*/)
                    next_state = S_MBINIT;
                else if (timeout_cnt > TIMEOUT_SBINIT)
                    next_state = S_TRAINERROR;
            end

            S_MBINIT: begin
                if (mbi_sub == MBI_DONE)
                    next_state = S_MBTRAIN;
                else if (timeout_cnt > TIMEOUT_MBINIT)
                    next_state = S_TRAINERROR;
            end

            S_MBTRAIN: begin
                if (mbt_sub == MBT_DONE)
                    next_state = S_LINKINIT;
                else if (timeout_cnt > TIMEOUT_MBTRAIN)
                    next_state = S_TRAINERROR;
            end

            S_LINKINIT: begin
                // Final sideband handshake confirming both sides ready for ACTIVE
                if (sb_msg_valid && sb_msg_type == 8'h03 /*SPEC-CHECK opcode*/)
                    next_state = S_ACTIVE;
                else if (timeout_cnt > TIMEOUT_SBINIT)
                    next_state = S_TRAINERROR;
            end

            S_ACTIVE: begin
                // IMPL-DEFINED: low-power entry triggers come from link layer/PM logic,
                // not shown here (power-management FSM is a separate concern)
                // Placeholder inputs would drive: -> S_L1, -> S_L2, -> S_PHYRETRAIN
                next_state = S_ACTIVE;
            end

            S_L1: begin
                // Fast wake path: skip most of MBINIT/MBTRAIN
                next_state = S_L1; // IMPL-DEFINED exit trigger -> S_LINKINIT (abbreviated)
            end

            S_L2: begin
                // Deep low-power: full retrain required on exit
                next_state = S_L2; // IMPL-DEFINED exit trigger -> S_SBINIT
            end

            S_PHYRETRAIN: begin
                if (retrain_cnt < MAX_RETRAIN_CNT)
                    next_state = S_MBTRAIN;
                else
                    next_state = S_TRAINERROR;
            end

            S_TRAINERROR: begin
                // IMPL-DEFINED: some errors are retryable (-> S_RESET), some are
                // terminal (-> S_DISABLED). The SB_MGMT_UP-drop case is a
                // concrete instance of the retryable class:
                if (trainerror_needs_handshake) begin
                    // Entered from MBINIT: sideband is still assumed usable,
                    // so hold here until the TRAINERROR handshake with the
                    // partner completes, then drop to RESET.
                    if (trainerror_handshake_done)
                        next_state = S_RESET;
                    // else: stay in S_TRAINERROR while the handshake runs
                    // (a small SB exchange FSM, not shown here).
                end else if (sb_mgmt_up_fell || !sb_mgmt_up) begin
                    // Entered from SBINIT: sideband management link is
                    // already down, so no handshake is possible -- drop
                    // straight to RESET.
                    next_state = S_RESET;
                end else begin
                    // All other TRAINERROR causes (timeouts, etc.) as before.
                    next_state = S_DISABLED;
                end
            end

            S_DISABLED: begin
                next_state = S_DISABLED; // requires external reset to exit
            end

            default: next_state = S_TRAINERROR;
        endcase
    end

    // =====================================================================
    // MBINIT sub-state machine
    // =====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mbi_sub <= MBI_IDLE;
        else if (state == S_MBINIT)
            mbi_sub <= mbi_sub_next;
        else
            mbi_sub <= MBI_IDLE; // reset sub-state on exit/entry
    end

    always_comb begin
        mbi_sub_next = mbi_sub;
        unique case (mbi_sub)
            MBI_IDLE:          mbi_sub_next = MBI_CLK_VALID;
            MBI_CLK_VALID:     mbi_sub_next = MBI_VALID_PATTERN; // IMPL-DEFINED: needs real clk-detect signal
            MBI_VALID_PATTERN: if (&lane_valid_pattern_detected)
                                   mbi_sub_next = MBI_LANE_REVERSAL;
            MBI_LANE_REVERSAL: mbi_sub_next = MBI_REPAIR; // IMPL-DEFINED reversal-correction logic
            MBI_REPAIR:        if (!(|lane_repair_needed))
                                   mbi_sub_next = MBI_SPEED_ID;
            MBI_SPEED_ID:      mbi_sub_next = MBI_DONE; // IMPL-DEFINED: real handshake over SB
            MBI_DONE:          mbi_sub_next = MBI_DONE;
            default:           mbi_sub_next = MBI_IDLE;
        endcase
    end

    // =====================================================================
    // MBTRAIN sub-state machine
    // =====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mbt_sub <= MBT_IDLE;
        else if (state == S_MBTRAIN)
            mbt_sub <= mbt_sub_next;
        else
            mbt_sub <= MBT_IDLE;
    end

    always_comb begin
        mbt_sub_next = mbt_sub;
        unique case (mbt_sub)
            MBT_IDLE:       mbt_sub_next = MBT_CAL;
            MBT_CAL:        if (&lane_calibration_done)
                                mbt_sub_next = MBT_VALID_PAT2;
            MBT_VALID_PAT2: mbt_sub_next = MBT_EYE_CHECK; // IMPL-DEFINED: pattern checker result
            MBT_EYE_CHECK:  mbt_sub_next = MBT_DESKEW;    // IMPL-DEFINED: margin thresholds, vendor PHY
            MBT_DESKEW:     if (clock_pattern_locked)
                                mbt_sub_next = MBT_LINK_TEST;
            MBT_LINK_TEST:  mbt_sub_next = MBT_DONE;      // IMPL-DEFINED: BER threshold / pattern-match count
            MBT_DONE:       mbt_sub_next = MBT_DONE;
            default:        mbt_sub_next = MBT_IDLE;
        endcase
    end

    // =====================================================================
    // Outputs
    // =====================================================================
    assign ltsm_state_top    = state;
    assign mbinit_substate   = mbi_sub;
    assign mbtrain_substate  = mbt_sub;
    assign link_active       = (state == S_ACTIVE);
    assign link_error        = (state == S_TRAINERROR) || (state == S_DISABLED);

    // Sideband message driving is intentionally left minimal — a real design
    // needs a dedicated SB packet FSM (CRC, retries, arbitration with other
    // SB traffic like register accesses) that this module would interface with.
    assign sb_msg_send     = 1'b0; // IMPL-DEFINED
    assign sb_msg_type_out = 8'h00; // IMPL-DEFINED

endmodule
