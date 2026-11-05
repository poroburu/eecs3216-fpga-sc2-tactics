# Intended demonstration

Target: approximately eight minutes. This is a planned demonstration, not a record
of working behavior. SC2 integration is required; an independent reference and
saved snapshots support verification but do not replace the game loop.

## Setup

- DE10-Lite connected to the host PC through a 3.3 V UART adapter with common ground.
- SC2 game graphics visible on the PC.
- FPGA VGA connected to a monitor showing colored unit markers, selected
  target/waypoint highlights, and tactical-state text.
- HEX/LEDs show result, cycle, and status information.
- Frozen supported map/client versions, selected policy revisions, and starting layouts.
- Single-step game mode; automatic hardware decisions plus a manual step mode
  for inspecting transitions. Real-time play is optional.

Before a run, confirm round reset, enrolled unit indices, initial maximum health,
and waypoint locations. Start with the supported Marine-versus-Zergling matchup.

## 1. Explain the boundary — about one minute

Show the live game and the schematic VGA display. Explain that SC2 handles
physics/pathfinding and actual damage; the FPGA selects tactics and targets.
The host transports facts and validates commands.

## 2. Approach and engage — about two minutes

Start outside weapon range with an objective waypoint near the encounter.
Show advance transitioning to attack, and inspect at least one returned target.
Distinguish weapon cooldown from an input/protocol failure.

## 3. Target allocation — about two minutes

Load a qualified starting arrangement with unequal enemy health. Single-step
the decision and show weakest-remaining-health ranking, deterministic ties where
applicable, and reservations affecting later attackers. Then resume the fight.
Explain that reservations represent estimated damage for this snapshot.

## 4. Retreat to safety — about two minutes

Use a starting force/health disadvantage that triggers the defined threshold.
Show RETREAT, a move toward the authored safe waypoint, and holding at arrival.
Show reset clearing retreat history for the next round.

## 5. Results and repeatability — about one minute

Reset a scenario and explain the matched comparison against Attack-Closest and
the selected MarineMicroBot policy. Present the recorded outcomes, surviving
health, game loops, core cycles, serial round-trip latency, and Quartus reports.

## Evidence to retain

- Map/client/API/policy versions, map hash, starting arrangement, opponent,
  seed where supported, and decision interval.
- Input snapshots, returned assignments, submitted actions, and error outcomes.
- Outcomes, survivors, remaining health, game loops, and timing measurements.
- Reference comparisons, simulation results, and Quartus utilization/timing.
- All failed or invalid attempts, with reasons, rather than only successful fights.

Success is correct, visible, repeatable FPGA control in the supported scenarios.
A particular win rate or speedup is an experimental result, not a prerequisite
invented from the demonstration's appearance.
