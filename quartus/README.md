# DE10-Lite UART projects

Target **10M50DAF484C7G**, Quartus Lite 25.1std.0 Build 1129, 50 MHz.
See [wiring and commands](../docs/uart-bringup.md).

- `bringup/uart_loopback.qpf`: source recovered from the earlier verified hardware
  thread. Direct GPIO echo plus a custom RX displaying the last six printable
  UART characters on HEX. Its private UART module belongs only to this project;
  do not mix it with `rtl/uart_rx.sv`.
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
