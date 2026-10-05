create_clock -name clk50 -period 20.000 [get_ports {CLK}]
derive_clock_uncertainty
# Asynchronous external buttons terminate at their first synchronizer stages.
set_false_path -from [get_ports {KEY_SW[*]}] -to [get_registers {*address_meta* *key_meta*}]
set_false_path -from [get_ports {RESET}]
