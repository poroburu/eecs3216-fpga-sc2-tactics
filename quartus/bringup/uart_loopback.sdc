create_clock -name clk_50 -period 20.000 [get_ports clk_50]
derive_clock_uncertainty
# The displays have no external capture clock or synchronous timing requirement.
set_false_path -to [get_ports {HEX*}]
# Bound the direct asynchronous UART input-to-output wiring delay to 100 ns.
set_max_delay 100.000 -from [get_ports uart_rx] -to [get_ports uart_tx]
# Only the first stage of the asynchronous UART synchronizer is exempt.
set_false_path -from [get_ports uart_rx] -to [get_registers {*|rx_meta}]
