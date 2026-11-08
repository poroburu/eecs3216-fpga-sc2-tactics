create_clock -name clk_50 -period 20.000 [get_ports clk_50]
derive_clock_uncertainty
set_false_path -from [get_ports uart_rx] -to [get_registers {*receiver|rx_meta}]
# UART output is asynchronous to the host; internal launch timing remains checked.
set_false_path -to [get_ports uart_tx]
