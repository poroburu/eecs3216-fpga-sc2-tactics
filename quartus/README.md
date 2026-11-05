# Planned Quartus project

Target board: DE10-Lite. Target device: **10M50DAF484C7G**.
No `.qpf`, `.qsf`, `.sdc`, pin assignments, or bitstream exist yet.

Create and review:

- Project/top-module selection and HDL file list.
- Pin assignments from the selected DE10-Lite manual revision.
- 50 MHz processing clock and generated-clock/timing constraints.
- PLL parameters for the proposed 25.2 MHz VGA pixel clock.
- Reset, asynchronous UART input, and clock-domain crossing design.

Use a 3.3 V UART adapter and common ground. The USB-Blaster is the programming
connection; the proposal's UART requires an external bridge through GPIO.

Keep source constraints and IP configuration in Git. Generated databases,
bitstreams, and reports are ignored. Retain selected measured report summaries
with the final results, identifying the source revision, tool version, and build.
Do not treat the proposed clock as timing closure until Quartus verifies it.
