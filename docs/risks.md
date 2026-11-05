# Risks and responses

Status: prospective risks; no integration or synthesis results are available yet.

## Map and scenario compatibility — high

Default AI Arena micro rounds may exceed unit counts, introduce unsupported
abilities/types, or use terrain outside the model.

- Check a downloaded map before freezing the proposal's scenario details.
- Select or minimally adapt a small supported matchup; pin the map bytes/version.
- Verify actual spawns, ownership, positions, health, resets, and visibility.
- A download link is not evidence that the map works with our selected client.

## SC2/API/client versions — high

An SDK example, map revision, or benchmark can depend on a different client/API.

- Prove one working combination in milestone 1 and preserve exact revisions.
- Recheck behavior after changing any part of that combination.
- Maintain runnable local setup instructions; do not assume another student's
  installation matches the tested one.

## Host/FPGA contract and command semantics — high

Old round IDs, dead units, visibility changes, malformed packets, or repeated
orders can produce invalid actions or interrupt useful attacks.

- Validate identifiers and command legality; preserve current visible facts.
- Commit complete input frames atomically; reject partial/oversized input.
- Test reset, death, disappearing targets, cooldown, and round transitions.
- Define HOLD and suppress redundant native orders; inspect actual actions/orders.
- Record errors and invalid runs instead of silently counting them as normal fights.

## Communication latency — high for real-time play

At 115,200 baud and 8-N-1, payload capacity is at most 11,520 bytes/s before packet
overhead. Transfer time may dominate the hardware computation.

- Require single-step SC2 initially; measure computation and round trip separately.
- Use an equal simulation decision interval for all gameplay comparators.
- Continuous real-time operation and a higher baud rate require separate tests.
- No end-to-end CPU speedup is assumed.

## HDL arithmetic, memory hazards, and timing — high

Incorrect signed widths, overflow, pipeline-valid handling, reservation ordering,
or clock crossings can corrupt decisions even when a short example looks right.

- Use independent known answers and randomized stateful sequences.
- Exercise maximum values, ties, exact range boundaries, empty inputs, and reset.
- Drain before dependent writes; protect active input records.
- Compile early and use actual Quartus resource and timing reports.
- Check coherent VGA handoff and UART input synchronization on hardware.

## Tactical quality and combat-model mismatch — medium/high

The health-times-damage score and retreat thresholds are heuristics. They omit
attack-rate differences, terrain, many game mechanics, and future impacts.

- Keep the initial matchup/terrain narrow and test threshold sensitivity.
- Treat damage reservations as estimates, not confirmed lethal hits.
- Vary starting conditions and preserve losing runs.
- Evaluate survivors, health, and outcomes; correct arithmetic alone does not
  establish better tactics or general SC2 capability.

## Benchmark validity — medium/high

MarineMicroBot is a small example controller specialized for Marines versus
Zerglings. Full-game bots need adaptation before serving as fixed-army controls.

- Pin and run the chosen example policy; document any changes.
- Compare controllers on matched starts with the same opponent and step interval.
- Keep Attack-Closest as a simple interpretable baseline.
- Do not attribute effects of different armies, map mechanics, or decision rates
  to the FPGA's algorithm.

## Schedule and scope growth — high

UART, HDL, a game host, maps, and video integration can consume the available time.

- Finish the software-controlled scenario early and integrate continuously.
- Keep VGA to markers/text, the four tactical states, and supported fixed armies.
- Defer production, mixed units, spells, complex navigation, learning, and ladder deployment.
- Freeze optional features before rehearsal; discuss assessed-scope changes with
  the instructor rather than silently dropping required behavior.

## Lab equipment and reproducibility — medium

The board, suitable 3.3 V serial adapter, VGA monitor, and a working SC2 PC may not
all be available during the final session.

- Check equipment and cabling early; rehearse the actual arrangement.
- Keep a tested setup guide, pin assignments, scenario inputs, and bitstream build
  procedure with version information.
- Retain logs/replays where available as supporting evidence. A recording does
  not replace the required live hardware demonstration.
