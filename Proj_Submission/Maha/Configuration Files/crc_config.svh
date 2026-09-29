`ifdef CONFIG_1024
  `include "crc_config_1024.svh"

`elsif CONFIG_512
  `include "crc_config_512.svh"

`endif

