# Architecture and draft decisions

Status: tactical design intent; UART/packet components are implemented.
The [v1 protocol](protocol.md) is the canonical wire/numeric contract.

## Responsibilities

- **SC2:** game simulation, pathfinding, collision, cooldown progression, attack
  resolution, and rendered game graphics on the PC.
- **PC host:** launch/join/step the game; acquire legal observations; convert
  units to stable indices and fixed-point records; exchange UART packets;
  validate returned commands; submit actions; record results.
- **FPGA:** strength estimation, tactical state, distance/range evaluation,
  target allocation, per-snapshot reservations, and decision diagnostics.
- **VGA:** a top-down schematic of unit markers, selected targets/waypoints, and
  state text. It does not receive or reproduce SC2 image frames.

In required single-step operation: observe, send snapshot, await/validate reply,
submit actions, then advance the game by the agreed number of loops. Measure
wall-clock latency separately from simulation time. Test timeout/error behavior;
an invalid reply is not a valid gameplay decision.

## Supported model

- Up to 16 records per side; initial demonstrations use 4–8 Marines versus 4–8
  Zerglings in open terrain without upgrades or abilities.
- Include only eligible current visible enemy facts. Unsupported records or
  oversized snapshots must produce an explicit error; do not silently truncate.
- Positive per-attacker damage estimates and effective reach are constant across
  the supported target type. Range conversion must account for the selected
  game's unit radii and coordinate units.
- Objective and retreat waypoints are scenario inputs, not targets chosen by a
  hidden software tactical controller.

## Tactical baseline

Use `S = sum(health_i * damage_per_attack_i)` over living units. This proxy ignores
attack-interval differences and is not a validated combat outcome predictor.

- Empty friendly squads hold.
- Trigger retreat when observed enemy strength is at least twice friendly
  strength, or total friendly health is at most 25% of initial squad maximum.
- Latch retreat until round reset; hold after arrival at the safety waypoint.
- Otherwise attack when a ready friendly unit has an eligible target in range;
  wait through an in-range cooldown; advance toward the objective when appropriate.
- Waypoint arrival tolerance is one map unit.

Finalize transition priority and per-unit behavior at milestone 2. Test the score
and cutoffs rather than attributing those exact values to the cited literature.

## Allocation baseline

Process ready attackers in stable index order. Rank eligible in-range targets by
positive health remaining after this snapshot's reservations, then squared
distance, then target index. Reserve estimated damage before the next attacker.
Unassigned attackers hold during attack allocation. Reset reservations for the
next snapshot; they are not an in-flight projectile/impact ledger.

## Planned datapath and control

- 50 MHz processing clock; PLL-derived 25.2 MHz VGA pixel clock.
- Unsigned 16-bit positions/reach with six fractional bits.
- Signed 17-bit coordinate differences and a 35-bit squared-distance sum.
- 16-bit health/damage with four fractional bits, 20-bit reservations,
  36-bit strength sums, and widened comparisons.
- Four distance/ranking pipeline stages; synchronous on-chip record memory.
- Master states: RECEIVE, VALIDATE, ASSESS, ALLOCATE, REPLY, ERROR.
- Separate tactical state and retreat history; drain scans before committing
  reservations; lock input memory during computation.
- Transfer coherent, completed display snapshots across clock domains with a
  handshake. Do not synchronize a changing multi-bit record one bit at a time.

## Host/FPGA contract

The [v1 contract](protocol.md) specifies framing, checksum, fields, numeric
bounds, commands, IDs, reset, retries and timeout behavior. See
[verification](verification.md) for tested components and integration gaps.

Before merging dependent implementations, obtain producer/consumer sign-off.
The session cache and tactical core must implement START, stale/duplicate IDs,
constant initial-health history and retreat persistence behind the packet
interface. Map/client qualification must establish observed round boundaries,
authored coordinates, effective reach/radii and native HOLD/order semantics.
The PC must fail explicitly on invalid hardware replies, never substitute tactics.
