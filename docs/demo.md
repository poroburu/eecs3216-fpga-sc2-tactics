# Demo plan: make the decision visible

Updated proposal presentation, November 12, 2026. Target: eight minutes.
The working demo commands are in the [executable runbook](demo-runbook.md)
and `tools/demo.sh`. This document scopes the updated presentation;
it is not a claim that the proposed strength/FSM/freeze features already run.
For the November 12 machine setup, custom Windows paths, and Linux commands,
use the [operating runbook](runbook.md).

## Setup and rehearsal checklist

Demo partner operates the checklist; lead handles faults and technical questions.
Connect the DE10-Lite, verified 3.3 V USB/UART wiring and ground, USB-Blaster,
SC2 host and VGA monitor. Use the actual tested client/map/build and preserve
their versions/hashes. Show game and FPGA VGA side by side.

Run baseline preflight/check first; repeat the board checker with each `SW0`
setting and retain logs. Prepare one recorded real snapshot that gives different
CLOSEST/FOCUS targets. Use a tested replay command for inspection, not a newly
invented button assignment. Resume/restart a live game after inspection.
PR #6 assigns `KEY0` reset, `KEY1` clear errors, `SW4:1` selected Marine;
do not promise a manual-step button without implementing and documenting it.

Prepare a matched seed for the reported defeat-to-victory comparison and a few
additional starts; label native result separately from mini-game score. Reset
between outcome comparisons. A mid-fight toggle shows immediate behavior, but
does not by itself establish a matched causal outcome comparison.

## 0:00–0:50 — the loop, in ordinary language

Use the [adapted CPS diagram](architecture.md):
“The game is our simulated plant. The PC measures positions and health, sends
them over UART, and applies the FPGA's answer. The board decides which enemy to
attack; the next game state feeds back into the next decision.”

Explain Marines as friendly units and Roaches as enemy units. SC2 handles motion,
combat and enemy waves; the PC does not choose friendly targets. Some built-in
auto-targeting is possible between FPGA decisions.

## 0:50–3:10 — same situation, different targeting

Run CLOSEST from the selected start. Ask the audience to watch target lines and
enemy health. Reset the same start, change the physical switch to FOCUS and run
again. Show the reported turnaround if reproduced; otherwise show measured
score/survivor differences without calling a score a victory.

Explain: “Finishing one enemy removes one source of damage. Spreading hits can
leave several enemies alive and firing.” FOCUS means weakest **in each unit's
range**, otherwise nearest; it is not a global lock onto one enemy.

## 3:10–4:30 — stop on one hardware decision

Replay the prepared snapshot unchanged under both switches. Select one Marine
and show policy, snapshot ID, target ID/HP, range status and squared distance.
Show subtract → square/sum → compare/min. VGA target lines make the output
readable without understanding SC2 tactics.

Explain the difference between target policy and state: “This changes whom we
attack. It does not yet say whether the squad should attack or retreat.” Keep
the transport FSM (IDLE/COMPUTE/REPLY/ERROR) distinct from tactical behavior.

## 4:30–6:00 — why the proposed tactical state changes

Only show live retreat once the extension gate has passed. Start with a clear
advantage, then a qualified disadvantage/low-HP case. Show `PF`, `PE`, threshold
reason and `ATTACK → RETREAT → HOLD at safety`. Show explicit encounter reset
clearing the latch. Use boundary snapshot replay to expose the exact comparison.

“The square-law strength estimate values keeping more weapons alive. It is a
small approximation, not a guaranteed prediction. The FPGA uses a specified
comparison to decide whether to keep fighting or preserve units.”

Judge this scene by units/HP preserved or survival time. A retreat can forfeit
the wave objective. If only bars exist, label them advisory and explain that
they are not controlling SC2; obtain course approval for any assessed-scope change.

## 6:00–7:15 — the FPGA contribution

- Show VGA continuing while UART receives/returns decisions.
- Show measured cycle count and link latency separately. PR #6 reports max
  258 clocks / 5.16 µs core versus 15.9 ms median round trip; replace with current
  build results after adding logic. Serial/USB dominates end-to-end latency.
- Inject a known bad-checksum frame with the test tool; point to the error and
  unchanged good snapshot, then send a valid frame to show recovery.
- Present the current Quartus timing/resource summary and independent reference
  check results. Explain predictable pipelined computation and concurrent I/O,
  not a claim that Python cannot compute these rules or that FPGA causes victory.

## 7:15–8:00 — evidence and roles

Show a compact table of matched starts/policies/results, board versus reference,
invalid/truncated runs and measurement definitions. Identify the lead's existing
implementation and each partner's delivered development/report/demo work.

Be ready for “Why FPGA?”: “This is a bounded hardware controller with custom
communication, a pipelined datapath, explicit control and continuous video output.
The game makes its decisions visible. We measure core predictability and verify
its outputs; we do not claim end-to-end CPU acceleration.”

## Evidence to retain

Source/bitstream/map hashes; client/API/tool versions; mode, seed and decision
interval; switch trace; raw observations/results; errors/truncation; native result
and score; survivors/HP; core cycles; end-to-end timing; Quartus setup/hold/resource
reports; each partner's handoff. Keep labeled logs/replays/video for support if a
live service fails, while preserving the live hardware/SC2 requirement.
