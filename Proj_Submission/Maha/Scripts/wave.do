onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /crc_tb/clk
add wave -noupdate /crc_tb/rst_n
add wave -noupdate -divider -height 30 {Input Flit}
add wave -noupdate -label start_of_packet /crc_tb/i_flit.start_of_packet
add wave -noupdate -label data_in_valid /crc_tb/i_flit.i_data_valid
add wave -noupdate -label data_in /crc_tb/i_flit.data_in
add wave -noupdate -label end_of_packet /crc_tb/i_flit.end_of_packet
add wave -noupdate -divider -height 30 {Output Flit}
add wave -noupdate -label data_out /crc_tb/o_flit.data_out
add wave -noupdate -label data_out_valid /crc_tb/o_flit.o_data_valid
add wave -noupdate -divider -height 30 {CRC Internal State}
add wave -noupdate /crc_tb/dut/crc_state
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {29989949 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {29881800 ps} {30137800 ps}
