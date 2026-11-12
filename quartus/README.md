# Quartus

- `common/de10_lite_pins.tcl`: pin and I/O-standard assignments, extracted from Intel's
  `DE10_LITE_Golden_Top` that ships with Quartus 25.1std.
- `sc2fpga/`: the demo project (`sc2fpga_top`, device `10M50DAF484C7G`, one 50 MHz clock).

```bash
tools/qbuild.sh quartus/sc2fpga sc2fpga     # compiles in a Windows temp copy; reports and .sof land in build/
tools/program.sh                            # JTAG, volatile
```

Measured utilization and timing are in [results.md](../docs/results.md). The UART adapter
must be 3.3 V. Its TXD goes to `GPIO[0]`, its RXD to `GPIO[1]`, and the grounds are shared.

## Earlier UART diagnostic (separate build and wire contract)

Use the [diagnostic contract](../docs/diagnostic-protocol.md), not the demo
frames above. The following retained instructions describe that diagnostic only.

Target **10M50DAF484C7G**, Quartus Lite 25.1std.0 Build 1129, 50 MHz.
See [wiring and commands](../docs/uart-bringup.md).

- `bringup/uart_loopback.qpf`: source recovered from the earlier verified hardware
  thread. Direct GPIO echo plus a custom RX displaying the last six printable
  UART characters on HEX. Its private UART module belongs only to this project;
  do not mix it with `rtl/diagnostic/uart_rx.sv`.
- `uart_diagnostic.qpf`: custom UART RX **and TX**, validated framed ingestion
  and serialized replies. START receives a transport ACK; snapshots receive
  UNSUPPORTED. It has no session cache/tactics and cannot benchmark gameplay.

`quartus_sh --flow compile uart_diagnostic` builds the diagnostic. Program the
volatile `.sof` via USB-Blaster. RX is JP1 pin 1/V10, TX pin 2/W10, clock P11;
verify wiring first. Unused pins are inputs tri-stated. Power-on reset lasts
255 cycles after configuration.

Generated databases/bitstreams/reports are ignored. Preserve measured summaries
and source hashes in `docs/evidence`. Diagnostic utilization/timing do not
establish utilization/timing of the future tactical core. In particular, Quartus
trims unused payload RAM in this diagnostic because no compute consumer reads it.
