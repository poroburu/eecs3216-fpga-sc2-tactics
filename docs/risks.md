# Risks and responses — updated proposal

November 12, 2026. Existing demo evidence is in
[PR #6](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/pull/6).
The Lanchester guard/tactical FSM is proposed, not part of that demo.

## Scope and integration — high

The target selector works, but friendly HP, retreat/hold, waypoints and explicit
encounter reset require protocol, HDL and host changes. Do not mistake a small
arithmetic block for a small complete integration.

- Freeze a bounded versioned contract/reference first; keep the demo build intact.
- Lead owns integration; development partner takes the bounded display/test work.
- Require live intents/reset/safety behavior by November 20; if missed, seek
  course scope revision rather than silently substituting advisory bars.
- Freeze features November 26. Defer kiting, reservations, mixed armies and maps.

## Tactical model and scenario mismatch — high

Lanchester's square law is an approximation. Equal counts do not imply equal
Marine/Roach strength; wounded units, geometry and waves violate ideal assumptions.
Retreat can preserve units while losing the mini-game objective.

- Use matchup-specific, documented integer effectiveness coefficients and a
  separate HP guard; calibrate on development starts and evaluate other starts.
- Show the computed values, state and exact guard reason. Label prediction errors.
- Keep FOCUS independent of the strength guard; compare one change at a time.
- Evaluate retreat by survival/remaining HP with a reachable safe point; do not
  promise the existing turnaround in every scenario or call all score gains wins.

## Protocol branches and native command behavior — high

PR #5 and PR #6 have different contracts. The older scaffold's 100 ms timeout,
RAM/PLL plan and four-stage pipeline do not describe PR #6's 10 ms timeout,
register records, pixel enable and three-stage target pipeline.

- Reconcile contracts explicitly; version changes and validate matching IDs/status.
- Reset the retreat latch on an explicit new encounter, not an empty wave gap.
- Test stale replies/session resets, deaths, no-enemy cases and max capacity.
- Specify HOLD and suppress redundant orders. Native attack/move cancellation
  can invalidate a visually plausible tactic; inspect actual API actions.
- No hidden software targeting fallback. After link failure, old native orders
  and auto-targeting may continue; count errors and mark affected runs.

## Hardware arithmetic and display — medium/high

The new square products and threshold multipliers need explicit widths and exact
boundary behavior. Display snapshots can change during a VGA frame.

- Test ties, equal thresholds, zero/max counts, HP limits, latches and reset
  against an independent reference; repeat on board under both switch settings.
- Refit the full design and retain setup/hold/resource reports.
- Preserve the single clock domain; add a frame-boundary swap for tear-free claims.
- Use small text/marker/bar additions; target-line rendering already consumes a
  significant part of the baseline design's resources.

## Evidence and latency — medium/high

PR #6's board tests and game parity were CLOSEST; its retained FOCUS score results
were software runs. User-reported later defeat-to-victory behavior needs matched
logs to support a reproducible hardware result.

- Record both board policies with the same start, versions, mode and step interval.
- Separate native result, map score, survivors and HP. Count invalid/truncated runs.
- Keep single-step evaluation; native auto-targeting may occur between decisions.
- Report core cycles and whole-link elapsed time separately. At 115200 8-N-1,
  throughput is at most 11,520 bytes/s before framing. Baseline median round trip
  15.9 ms is much larger than maximum reported core computation 5.16 µs.
- Do not claim CPU acceleration, power savings or hard real time without evidence.

## Equipment and team handoffs — medium

- Development partner needs a board, verified 3.3 V UART adapter, VGA and tool setup
  for independent work; first acceptance is reproducing a baseline board check.
- Report partner works from traceable logs/citations; demo partner rehearses with
  the lead's hardware and owns setup, timing and repeatability.
- Keep exact build/setup commands and supporting recordings/logs, but preserve
  the live hardware/SC2 demonstration requirement. Record actual contributions.
