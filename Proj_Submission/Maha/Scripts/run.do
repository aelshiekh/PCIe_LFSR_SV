vlib work
# Choose Configuration: CONFIG_512 or CONFIG_1024
# Turn ON/OFF option to split 1024 config into 2 cycles: SPLIT_1024_CONFIG or NO_SPLIT_1024_CONFIG
vlog -f source_files.txt +define+CONFIG_1024 +define+NO_SPLIT_1024_CONFIG
vsim -gui work.crc_tb -voptargs=+acc
do wave.do
run -all
