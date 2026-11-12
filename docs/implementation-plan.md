# Implementation and realistic team allocation

Updated November 12, 2026. The lead implemented the existing demo in
[PR #6](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/pull/6).
The user reports provisional TA approval of that demo. The
[updated proposal](proposal/proposal.pdf) adds one bounded Lanchester-inspired
extension; expanded scope/Tier A remain subject to course approval.

## Ownership that matches available people and equipment

Names/IDs are still unassigned. Record actual contributions as work is delivered;
future delegation does not imply other members wrote the existing implementation.

| Role | Owns from now on | Concrete handoff and acceptance | Boundary |
|---|---|---|---|
| **Project lead — you** | Scope, algorithm/reference specification, tactical FSM, protocol changes, SC2 command integration, review, final build and submission | Freeze interfaces; integrate a live reference-matching controller; approve evidence and final report | Accountable for critical integration; do not assume four independent HDL developers. |
| **Development partner — independent board, UART adapter and VGA access** | Reproduce baseline locally; strength-bar/state/reason renderer using an agreed register interface; assist reference, simulation and board regression | Setup notes plus own board test log; display module with known-value bars/state labels; baseline both-policy checker results | Lead supplies interface/fixtures and reviews changes. No separate host rewrite or map work. Start with a small display module if HDL experience is limited. |
| **Report partner — no independent hardware required** | Report outline, citations, adapted CPS explanation, methods, results tables, limitations and contribution log | Draft sections and source-linked tables; each number identifies commit, policy and test type; compile/check one-page proposal and final report | Lead verifies technical claims. Do not invent measurements or assign this member core RTL. |
| **Demo partner — works with lead's hardware** | Equipment/setup checklist, seeds and scenario manifest, matched-run logging, freeze/reset presentation flow, rehearsal timing and narration | Repeated setup from cold start with checklist; labeled baseline/FOCUS logs; an eight-minute rehearsal and backup evidence set | Operates tested commands, records evidence and explains the demo. Does not need to design algorithms or own a board. |

Each partner gets one initial deliverable that can be reviewed without blocking
the lead: setup replay, report outline, or demo checklist. Agree a short check-in
and preserve delivered files/commits so support work is visible in the report.
Use issues and PRs per [CONTRIBUTING](../CONTRIBUTING.md); do not close existing
transport/protocol issues just because a separate demonstration branch works.

## November 12–13 — proposal and baseline evidence

- Lead: submit the rescope based on the actual Marine/Roach demo; identify
  current versus planned functionality and provisional versus final approval.
- Development partner: obtain equipment and reproduce programming/checker setup;
  record the demo commit and bitstream hash.
- Demo partner with lead: retain the reported defeat-to-victory run's exact setup;
  check both physical policies and record missing board FOCUS comparison evidence.
- Report partner: assemble outline, references and textbook-adapted architecture.

Acceptance: current demo remains runnable, draft is one page, and the comparison
does not substitute software scores for board FOCUS trials.

## November 14–20 — one controlled extension

- Lead freezes fixed-point coefficients, numeric bounds, guard priority,
  friendly-HP/reset semantics, versioned wire contract and independent reference.
- Lead implements bounded strength arithmetic and ATTACK/RETREAT/HOLD, adds
  native MOVE/HOLD mapping, and qualifies a reachable safe point.
- Development partner adds strength bars/state/reason to the existing VGA output
  with fixed known-value inputs first; then checks the lead's integration.
- Both developers test equality/threshold boundaries, empty sides, maximum
  counts, HP threshold, retreat latch, ID/reset and enemy-wave transitions.
- Report/demo partners build evidence templates and scene explanations in parallel.

**November 20 gate:** reference/protocol, live orders, reset and safe-point
behavior must work together. Display-only bars do not satisfy the tactical
extension. If this cannot pass, retain the baseline, seek course scope revision
and explicitly label the strength score advisory; do not silently drop the FSM.

## November 21–26 — integrate and freeze

- Integrate display, protocol and tactics without changing the established
  CLOSEST/FOCUS behavior. Keep the old build available for regression.
- Run independent directed/random/stateful reference checks, replayed SC2
  snapshots and actual board checks under both switch settings.
- Compile the complete extension for the exact device; retain resource and
  setup/hold reports. Do not reuse baseline fit numbers as extension results.
- Prepare replay of a single frozen snapshot, explicit policy/state/reason
  labels, and a controlled checksum-error/recovery demonstration.
- Freeze features November 26. No kiting, mixed-army/map-editor work or additional
  policies unless all assessed core behavior is already complete.

## November 27–December 1 — measure, write and rehearse

- Demo partner runs the matched scenario checklist with the lead: same seed,
  map/client, bitstream and eight-loop decision interval; change one policy only.
- Report partner records outcome/score, survivors/HP, valid/invalid runs and
  separate core/link timings. Tune on development starts; evaluate other starts.
- Lead validates claims and confirms no truncated snapshots are treated as clean
  comparisons. Record guard prediction errors as well as successes.
- Rehearse the [eight-minute demonstration](demo.md) with game and VGA visible.
  Explain retreat by preservation of units, not an automatic victory claim.
- Keep logs, bitstream/build steps and short labeled recordings as supporting
  evidence. They do not replace required live hardware or SC2 integration.

## Course dates

- Proposal: November 13, 2026, 23:59.
- In-person demonstration: December 2, 2026, 16:00–18:50.
- Final report and code: December 2, 2026, 23:59.

Required scope: preserve the working FPGA/SC2 A/B target selector, verified custom
hardware and VGA; integrate the proposed bounded guard/FSM subject to course
approval. Defer reservations, kiting, full path planning, production, abilities,
learned policies, competitive ladder play and external-bot benchmarking.
