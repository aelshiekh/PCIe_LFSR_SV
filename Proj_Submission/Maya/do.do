if {![file exists work]} {
    vlib work
}

vmap work work

# Compile RTL + testbench
#vlog +define+CRC_512 \
#vlog +define+CRC_1024 \
vlog +define+CRC_1024 +define+CRC_1024_SPLIT \
    +incdir+rtl \
    rtl/crc_pkg.sv \
    rtl/crc_calculator.sv \
    rtl/crc_dut.sv \
    rtl/crc_ref.sv \
    tb/tb_pci_crc.sv

# Simulate
vsim -voptargs=+acc work.tb_pci_crc

# Add Ref signals to waveform
add wave -divider "CRC Ref"
add wave /tb_pci_crc/Ref/data_in
add wave /tb_pci_crc/Ref/data_out

# Add DUT signals to waveform
add wave -divider "CRC DUT"

add wave /tb_pci_crc/DUT/clk
add wave /tb_pci_crc/DUT/rst_n

add wave -divider "Packet Input"
add wave /tb_pci_crc/DUT/pkt_in

add wave -divider "Packet Output"
add wave /tb_pci_crc/DUT/pkt_out


# Run simulation
run -all