# Updated proposal scope — November 12, 2026

The submission draft is [proposal.tex](proposal.tex), with its compiled
[one-page PDF](proposal.pdf). This note records the rationale behind that short
proposal. The existing demo has provisional TA approval, as reported by the lead;
the expanded scope and Tier A assessment still need course approval. No tactical
feature is implemented by this documentation change.

Tracked in [work item #7](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/issues/7).

## Start from the demo that exists

Source: [PR #6](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/pull/6),
reviewed at commit `7ce3b0e924949c3fc2966cbacd9eeae0be07a2f2`.
This proposal branch starts from the earlier scaffold; it does not merge the
implementation or resolve protocol differences with PR #5.

- Live SC2 **DefeatRoaches**: Marines against waves of Roaches; homogeneous units
  on each side, capacity 16 per side, observed demo counts at most 10 and 4.
- CLOSEST minimizes `(distance_squared, enemy_index)`.
- FOCUS minimizes `(out_of_range, in_range ? HP : 0, distance_squared,
  enemy_index)`. It chooses the weakest enemy in each Marine's range, otherwise
  the nearest. It does not force every Marine to share a target.
- Custom UART at 115200 8-N-1, three-stage pair pipeline, register-based records,
  VGA markers/target lines, HEX and LED status. One 50 MHz domain and a 25 MHz
  VGA pixel enable; no record RAM, PLL or display clock crossing in this design.
- Host submits the FPGA's target as an SC2 attack order; SC2 supplies pathing,
  movement into range, cooldowns, firing, damage and some idle auto-targeting.
- No strength estimate, tactical retreat/hold FSM, waypoints, damage reservations
  or friendly HP/cooldown fields exist in this demo protocol.

The lead reports that toggling tactics changed a demonstrated defeat to victory.
Keep that as the opening motivation. Retained November 8 evidence is narrower:
software CLOSEST/FOCUS mean scores were 32.1/62.4 over seeds 1–10; board CLOSEST
matched its reference game for game; recorded board FOCUS trials were still open.
Score in a wave mini-game is distinct from binary win/loss. Retain the exact seed,
build, run mode and result for the turnaround before presenting it as a
reproducible hardware comparison. No gameplay was rerun for this draft.

## Shortlist, in recommended order

| Candidate | Implementation and VGA explanation | Value and scope decision |
|---|---|---|
| **Nearest vs weakest-in-range focus fire** | Existing distance pipeline and lexicographic minimum; target lines, enemy HP labels, distinct-target count | **Main demonstration.** Early kills remove enemy weapons. Lowest implementation risk and strongest existing scenario evidence. |
| **Lanchester-inspired engage/retreat guard** | Living-unit counts, square lookup, two coefficient products and widened comparisons; strength bars, tactical state and reason | **One planned extension.** Connects a computed quantity to a change in order type. Arithmetic is small; protocol, reset and live movement integration are the real work. |
| **Target hysteresis / switching penalty** | Prefer a still-valid prior target unless another improves by a fixed margin; store prior target, display change count | Optional if logs show churn. Low arithmetic cost but stateful tag/index handling; may delay finishing weakened enemies. |
| **Damage reservations / no-overkill** | Ready-attacker allocation, residual-HP ledger; show predicted damage stacked against HP | Lower priority. Existing software mean 61.4 versus FOCUS 62.4 shows no benefit at eight-loop decisions. Requires readiness/damage fields and dependency handling. |
| **Cooldown-aware kiting** | Fire when ready, otherwise move toward a bounded retreat point; ATTACK/MOVE alternation, cooldown and trails | Visual stretch with greater cost. Needs movement, cooldown and attack-cancellation checks; do not promise win improvement. |

Weakest targeting, no-overkill and kiting have precedents in
[Churchill and Buro, Sec. III](https://davechurchill.ca/publications/pdf/combat13.pdf).
These priorities use the demo evidence; full portfolio search is out of scope.

## A bounded Lanchester implementation

Use the square law as an **explainable strength heuristic**, not a combat oracle.
It motivates preserving live weapons; focus fire is the separate allocation rule
that tries to remove enemy weapons. It does not prove FOCUS wins an SC2 fight.

For homogeneous armies on each side, let `F` and `E` be living-unit counts:

```text
dF/dt = -kE * E          dE/dt = -kF * F
PF = kF * F²            PE = kE * E²
```

`kF` represents friendly effectiveness against the selected enemy type; start
with a proportional estimate `DPS_F / enemy_max_HP`, and conversely for `kE`.
Damage per attack alone omits firing rate. Store scaled integer constants for
this matchup; record scale, source, rounding and calibration. Convert constants
offline, not in a hidden live host policy. Use same-type versus same-type saved
examples to explain `F²`; qualify unequal Marine/Roach coefficients for live bars.

Classic assumptions include continuous attrition, homogeneous units per side,
fixed effectiveness, rapid retargeting and broad participation. Geometry, wounded
units, focus fire, discrete volleys and waves can break them. The
[StarCraft Lanchester paper](https://cdn.aaai.org/ojs/12780/12780-52-16297-1-2-20201228.pdf)
extends the basic model; our fixed square-law guard is a simpler adaptation,
not its fitted predictor.

Proposed versioned extension, to freeze before RTL:

1. Preserve existing ranking rules and the three-stage target pipeline.
2. Add friendly HP, explicit encounter/session reset, authored safe waypoint,
   tactical state/reason and ATTACK/MOVE/HOLD intent. Freeze field widths, version,
   frame sizes, timeout and validity rules with host/RTL owners. Do not silently
   change PR #6 frames or reuse PR #5 bytes.
3. Count `0..16` living units and read squares `0..256` from a 17-entry table.
   Proposed 16-bit unsigned coefficients give at most `65535*256=16776960`
   (24 bits); use at least 26 bits for the factors of four in comparisons.
   Recompute bounds if scales change. No square root, division or ODE solver.
4. Transition priority: empty friendly squad → HOLD; prior retreat latch →
   RETREAT or HOLD at safety; empty enemy squad → HOLD; otherwise latch RETREAT
   if `4*PF < 3*PE` or `4*total_friendly_HP <= encounter_initial_max_HP`;
   otherwise ATTACK. Zero coefficients are invalid configuration.
   The 0.75 and 25% cutoffs are engineering parameters, not literature constants.
5. Reset the retreat latch only on an explicit new encounter/reset, not an empty
   enemy list between waves. Capture initial squad maximum HP once; define
   reinforcement/death handling before testing. In RETREAT, move to the authored
   safe point; HOLD within one map unit. HOLD means no fresh command, preserving
   the arrived move; it is not automatically SC2 `HoldPosition`. ATTACK keeps
   native attack movement into range. Do not add a separate ADVANCE state yet.
6. Return state reason, raw strengths, counts and HP totals in diagnostics. Host
   validates/translates FPGA intent; it cannot make the guard decision. Reset,
   stale-session/ID and native command tests must pass before live use.

This controls **whether/how to engage**, while CLOSEST/FOCUS controls **whom to
attack**. Existing transport states (`IDLE → COMPUTE → REPLY`, plus ERROR) are
separate from proposed tactical states (`ATTACK / RETREAT / HOLD`).

A display-only strength milestone is useful but does not complete the proposed
tactical extension. By **November 20**, require frozen reference/protocol,
live ATTACK/MOVE/HOLD mapping, reset and safe-point behavior. If integration
cannot pass, seek a course scope amendment and label bars advisory.

## Make the FPGA contribution visible

The A/B fight demonstrates **algorithm value**. Snapshot inspection demonstrates
**hardware implementation value**. A CPU can implement these rules; victory
alone does not establish that an FPGA is necessary.

- Explain the [adapted feedback architecture](../architecture.md): measure →
  communicate → decide → actuate → measure.
- Replay one real snapshot unchanged under both physical switch settings. Label
  policy, snapshot ID, selected Marine, target HP and distance; lines show which
  comparisons changed. A dedicated freeze button does not exist in PR #6.
- Show pipeline stages and reported core cycles beside UART/host elapsed time:
  one pair per clock; `F*E+2` reported cycles for nonempty inputs, maximum 258
  clocks = 5.16 µs at 50 MHz; one reported clock for an empty side. This is
  datapath latency, not the full transaction.
- Show VGA timing continuing during communication. The current renderer holds
  completed records, but does not explicitly swap at vertical blank. Add a
  frame-boundary swap if tear-free updates are claimed.
- Send a known bad-checksum request using the checker; show explicit error,
  retained good snapshot and recovery.
- Present fitted resources for the actual build. PR #6 reports 32% logic
  elements, 68 embedded 9-bit multiplier elements, zero memory bits/PLLs and
  +4.283 ns setup slack. Much hardware draws target lines; refit extensions.
- Separate reported median round trip (15.9 ms) from maximum core time (5.16 µs).
  Do not infer end-to-end CPU acceleration, power savings or hard real time.

## Evidence and acceptance

Keep the baseline stable while adding one extension. Require independent
reference agreement over directed boundaries, recorded snapshots and random
sequences, plus actual board tests under **both switches**. The 1,216 PR board
tests ran with CLOSEST; simulated FOCUS coverage is not a recorded board FOCUS
check. These tests sample the specification, not exhaust every input.

For matched live runs retain commit/bitstream hash, map hash, client/API, seed,
step/realtime mode, eight-loop decision interval, policy trace, native result,
map score, survivors/HP, cycles, round trip, invalid frames and truncated
snapshots. Freeze coefficients/thresholds using development starts, then evaluate
additional starts. Match all non-policy conditions; mark invalid/truncated runs.
Ten seeds are a small benchmark, not a general win-rate claim.

Retreat needs a reachable safety point and a separate success criterion:
units/HP preserved or time survived. Running away can lose a wave objective.
Use a supported live setup and saved boundary snapshots; avoid a map-editor
project. Do not require every scene to end in victory.

## Ownership and dates

The lead completed implementation to date. See the
[implementation plan](../implementation-plan.md) for concrete future delegation.
Names/IDs remain placeholders; retain an honest contribution log.

Proposal due November 13, 23:59; extension gate November 20; freeze November 26;
evaluation/rehearsal November 27–December 1; demo December 2, 16:00–18:50;
report/code December 2, 23:59.
