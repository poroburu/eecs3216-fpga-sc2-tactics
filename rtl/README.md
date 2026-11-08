# RTL (SystemVerilog)

These modules implement the [protocol](../docs/protocol.md). The data flow is explained
in [how-it-works](../docs/how-it-works.md).

| Module | Role |
|---|---|
| `sc2fpga_pkg.sv` | Widths (`CW` = 11-bit Q7.4 coordinates, `D2W` = 23-bit d², 36-bit key), sync bytes, status codes |
| `uart_rx.sv` / `uart_tx.sv` | 8-N-1 UART, `CLKS_PER_BIT` = 434 at 50 MHz; 2-flop RX synchronizer, mid-bit sampling, stop-bit check |
| `frame_rx.sv` | Request parser FSM, running checksum, 10 ms inter-byte timeout, count and range checks, staging → committed copy in one clock |
| `target_select.sv` | 3-stage pipeline (DIFF → SQUARE → SELECT), one pair per clock, running minimum of the concatenated key |
| `frame_tx.sv` | Reply serializer and checksum |
| `vga_timing.sv` / `vga_render.sv` | 640×480@60 timing on a 25 MHz pixel enable; 4-stage renderer: unit markers plus a line from each Marine to its target (cross-product test, 32 multipliers) |
| `hex7seg.sv` | Active-low 7-segment decoder (hex digits, blank, `-`) |
| `sc2fpga_top.sv` | Board top: control FSM (IDLE / COMPUTE / REPLY / ERROR), display registers, HEX/LED, pin mapping |

Everything is in one 50 MHz clock domain. Asynchronous inputs (UART RX, `SW`, `KEY`)
pass through 2-flop synchronizers. Original work of the group; no IP cores are used.
