// ============================================================
// CRC configuration selection
// ============================================================

`ifdef CRC_512

    `ifdef CRC_1024_SPLIT
        `error "CRC_1024_SPLIT requires CRC_1024"
    `endif

    `include "crc_config_512.svh"


`elsif CRC_1024

    `include "crc_config_1024.svh"

    `ifdef CRC_1024_SPLIT
        `define CRC_USE_SPLIT
    `endif


`else

    `error "No CRC configuration selected. Define CRC_512 or CRC_1024."

`endif