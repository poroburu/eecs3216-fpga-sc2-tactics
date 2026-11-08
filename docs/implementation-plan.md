# Implementation plan

Status: proposed schedule, November 5, 2026; UART/protocol work started November 8.
See [verification](verification.md) for current evidence and remaining work.
The [proposal](proposal/proposal.pdf) defines the intended assessed scope;
instructor approval is pending.

## Milestone 1 — Prove the scenario setup, by November 13

- Launch an existing AI Arena micro map using a software-only host.
- Check its round rules and select or minimally adapt supported Marine-versus-
  Zergling scenarios. Do not assume every default round fits the hardware model.
- Verify 4–8 units per side, open terrain, ownership, observation visibility,
  actual spawns, resets, and objective/retreat waypoint placement.
- Run an Attack-Closest baseline and evaluate the MarineMicroBot example policy
  as the first named open-source comparator.
- Pin the working client/build, map bytes/hash, API, and comparator revisions.
- Confirm single-step SC2 operation and record the step interval.
- Bring up board programming and a UART loopback in parallel where equipment permits.

Acceptance: a repeatable, software-controlled SC2 fight with recorded setup and
commands, plus an agreed supported scenario. Neither map compatibility nor a
working benchmark is established by this scaffold.

## Milestone 2 — Agree the interface and reference model

- Specify framing, lengths, checksum, reset/error behavior, snapshot/round IDs,
  and stable unit indices.
- Define input facts, fixed-point conversion, range geometry, command semantics,
  numeric bounds, and rejection conditions.
- Define capture of initial friendly maximum health and how death/round reset
  affect it.
- Implement an independent fixed-point software reference for strength, tactical
  states, ranking, and reservations.
- Produce known-answer fixtures before integrating the HDL.

Acceptance: producer and consumer owners agree the contract; reference cases
cover ties, boundaries, empty inputs, cooldown, retreat, and round reset.
The [v1 wire contract](protocol.md) and byte fixtures are implemented;
producer/consumer sign-off and tactical reference work remain pending.

## Milestone 3 — FPGA core, November 14–20

- Build UART RX/TX, framing, checksum, timeout, and record memory loading.
- Implement the distance/range/ranking pipeline and strength accumulators.
- Implement the tactical FSM and sequential allocation/reservation controller.
- Protect input memory while computing; drain the pipeline before reservation writes.
- Compile for the exact MAX 10 device early; inspect utilization and timing.
- Verify ModelSim behavior against independent known answers and 1,000 randomized
  snapshot sequences, including state history.

Acceptance: valid snapshots yield reference-matching decisions; invalid packets
cannot partially update an active computation. Resource and timing results must
come from the actual Quartus design.

## Milestone 4 — SC2 and display integration, November 21–26

- Translate current game observations to the agreed packets.
- Submit only validated responses for the matching round/snapshot and unit tags.
- Deduplicate unchanged orders and test attack persistence.
- Exercise deaths, disappearing targets, empty squads, and consecutive rounds.
- Implement VGA timing, marker/text rendering, coherent display-data transfer,
  HEX diagnostics, and automatic/manual stepping.

Acceptance: FPGA decisions visibly drive approach, engagement, allocation, and
retreat in supported SC2 scenarios. The PC performs game/API/transport duties,
not a hidden replacement friendly tactical policy.

## Milestone 5 — Freeze, evaluate, rehearse, November 27–December 1

- Freeze several scenario starts and repeat matched runs with the FPGA,
  Attack-Closest, and the qualified MarineMicroBot comparator.
- Keep own army, opponent, map/client, starting conditions, and decision interval
  matched when comparing controllers. Document any comparator adaptation.
- Vary positions, health, and force balance to test reactions to observations.
- Record outcomes, survivors, remaining health, game loops, invalid runs,
  computation cycles, and end-to-end latency.
- Save Quartus resource/timing reports and prepare the final report/code archive.
- Rehearse the [demonstration](demo.md); freeze optional features.

Acceptance: reproducible functional demonstrations and an honest measurement
record. Winning every scenario, beating every comparator, and CPU speedup are
not assumed outcomes.

## Proposed workstreams

- **Student 1 — UART/host:** protocol tests, serial loopback, SC2 tag and command
  mapping, transport, and round resets.
- **Student 2 — Datapath:** fixed-point reference, arithmetic widths, overflow,
  distances, thresholds, and ranking ties.
- **Student 3 — FSM/allocation:** tactical transitions, retreat persistence,
  reservation dependencies, empty/cooldown cases, randomized sequences.
- **Student 4 — VGA/integration:** timing and clock crossings, scenario/benchmark
  qualification, integration, resource reports, and demo evidence.

Actual names and owners are unassigned. Share host/scenario work across the team
so integration is not deferred to the final week. A three-person team should
redistribute these workstreams explicitly.

## Scope control

Required: the bounded SC2 control loop, verified hardware, schematic VGA output,
and measured results. Defer continuous real-time operation, mixed armies, spells,
production, complex terrain, learned policies, and competitive ladder deployment.
Change assessed commitments through the course proposal process if needed.
