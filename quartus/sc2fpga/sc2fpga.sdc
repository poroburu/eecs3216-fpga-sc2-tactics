# Single 50 MHz clock domain (VGA uses a 25 MHz pixel enable, not a second clock).
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Asynchronous inputs (UART RX, switches, keys) pass through 2-flop synchronizers.
set_false_path -from [get_ports {GPIO[*] SW[*] KEY[*]}]
# Board outputs (LED/HEX are static; UART TX and VGA change far slower than the clock period).
set_false_path -to [get_ports {LEDR[*] HEX*[*] VGA_* GPIO[*]}]
