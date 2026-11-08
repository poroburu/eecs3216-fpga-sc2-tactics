# Architecture and draft decisions

> **Demo status (November 8, 2026):** the working demo implements the narrower contract in
> [protocol.md](protocol.md) (target selection only). The strength, retreat and reservation
> design below is the original proposal and is not implemented.

Status: design intent. No modules or packet layout are implemented.

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

## Draft host/FPGA contract

UART starts at 115,200 baud, 8-N-1. Frames will include a length and 8-bit additive
checksum. Reject invalid records/counts/checksums and a 100 ms inter-byte timeout.

Inputs include round/snapshot IDs, stable unit indices, health/max-health,
positions, damage estimates, friendly readiness, and objective/retreat waypoints.
Outputs include matching IDs, status, squad state, per-unit attack/move/hold
intent, target index or waypoint, and computation cycles.

Before implementation, settle:

- Exact wire encoding, endianness, field widths, and checksum coverage.
- Reset/start handshake, retry behavior, timeouts, and complete-frame commit.
- Bounds, fixed-point rounding, overflow policy, zero-damage handling, and range tests.
- Unit index/tag lifetime and round detection; use observed round boundaries.
- Initial maximum-health capture and behavior after board reset mid-round.
- HOLD semantics and order deduplication. Do not equate HOLD with repeatedly
  issuing SC2 HoldPosition or cancelling an attack; validate the native mapping.
- Result freshness and validation; explicit failure behavior rather than a
  silent software replacement for faulty FPGA decisions.

Keep this document aligned with the eventual executable contract and fixtures.
