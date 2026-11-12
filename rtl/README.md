# UART and packet RTL

SystemVerilog, synchronous active-high reset, one 50 MHz clock:

- `uart_rx`: two-flop synchronization, start confirmation, LSB-first 8N1, stop-bit
  error and break recovery. Divider 434 gives 115207.37 baud (+0.0064%).
- `uart_tx`: ready/valid byte input, full start/data/stop timing.
- `packet_rx`: v1 framing, count/record/numeric validation, additive checksum,
  5,000,000-clock timeout and double-buffered atomic payload commit. Metadata
  remains stable until `packet_ready`. Payload reads have one-clock latency;
  only read below payload length. Hold `packet_ready` low while computing.
  Unsolicited bytes while committed are dropped and counted.
- `packet_tx`: envelope/checksum serialization with byte backpressure; caller
  holds metadata and combinational payload data stable until `done`.

The receiver validates frame shape/fields, not session history. The eventual
consumer must implement START, stale IDs, full-byte duplicate cache, initial-health
consistency and tactical state from [protocol](../docs/protocol.md). The Quartus
diagnostic returns UNSUPPORTED for snapshots and is not that consumer.

See [sim](../sim/README.md). Distance/ranking pipeline, strength assessment,
allocation/reservations, tactical FSM, VGA and full controls remain unimplemented.
