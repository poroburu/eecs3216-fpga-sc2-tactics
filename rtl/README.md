# Planned RTL

Implementation language: SystemVerilog. No RTL is implemented yet.

Planned modules:

- UART receiver/transmitter, baud timing, input synchronization.
- Packet parser, additive checksum, timeout and validation controller.
- Unit/result/reservation memories and protected loading.
- Four-stage distance/range/ranking datapath.
- Strength accumulation and threshold comparison.
- Tactical FSM, retreat history, sequential allocation controller.
- VGA timing, marker/text rendering, HEX/LED drivers, and coherent display handoff.
- Board-level top module and synchronized/debounced controls as required.

Use the [architecture](../docs/architecture.md) and agree the interface before
creating dependent modules. Keep arithmetic widths, pipeline valid timing,
reservation ordering, reset behavior, and memory latency explicit.
