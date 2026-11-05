# Planned simulation

No testbenches, simulator project, or passing test results exist yet.

Use ModelSim-compatible SystemVerilog testbenches and an independently written
software reference. Keep expected outputs independent of the implementation.

Required coverage includes UART timing/framing/checksum/timeout, incomplete or
oversized packets, fixed-point boundaries, ties, pipeline valid/drain behavior,
reservation dependencies, tactical thresholds, retreat persistence, empty inputs,
cooldown, board reset, and round reset.

The proposal targets bit-exact results on 1,000 randomized snapshot sequences,
plus explicit known-answer cases. Add actual run commands, fixture formats,
simulator version, and result interpretation when tests are implemented.

Simulation validates the modeled contract. It does not establish SC2 command
acceptance, synthesized timing, or live gameplay benefit.
