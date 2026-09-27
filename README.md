# PCIe_LFSR_SV
Design Requirement:
 Given the CRC polynomial specified in the Appendix K in the PCIe spec, design a synthesizable SystemVerilog CRC calculation block that:
  - Calculates an 8-byte (64-bit) CRC over a 2048-bit packet.
  - Inserts the calculated CRC into the corresponding Flit at the required location.
  - Supports two input datapath configurations:
    - 1024-bit input per cycle → packet arrives in 2 cycles
    - 512-bit input per cycle → packet arrives in 4 cycles
  -  The CRC result must be calculated incrementally across the incoming cycles while maintaining the correct CRC state.
  - The design must support packet boundaries using SOP and EOP.

 Input Packet Interface: The input packet shall be represented using a packed SystemVerilog struct.
 The structure shall contain at least:
  - sop — Start Of Packet
  - eop — End Of Packet
  - data_in — Parameterized packet data. Data width is DATA_W shall be derived from the project configuration.
