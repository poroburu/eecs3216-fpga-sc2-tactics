# Planned SC2 host and reference model

No host executable, API dependencies, or reference model are implemented yet.

## Adapter duties

- Launch/join a qualified map, obtain legal observations, and control stepping.
- Map native unit tags to stable per-round packet indices.
- Capture initial squad maximum health and authored waypoints.
- Convert positions, health, damage estimates, effective reach, and readiness
  to the agreed fixed-point representation.
- Exchange framed UART packets; validate reply IDs, status, actors, and targets.
- Map attack/move/hold intents to native commands without repeated-order damage.
- Record observations, decisions, submitted commands, outcomes, and latency.

SC2 executes physics and pathfinding. The host must not silently replace a failed
FPGA reply with an unreported friendly tactical decision.

## Reference and benchmarks

The independent fixed-point reference checks hardware correctness. Attack-Closest
and a pinned MarineMicroBot policy compare gameplay behavior; they are distinct
from the correctness oracle. Keep the same opponent and step interval for matched
policy runs.

The official C++ SDK/example is the initial integration candidate. Final host and
reference language/tool versions are a milestone-1/2 decision. Add executable
setup/build/run instructions only after proving that path.
