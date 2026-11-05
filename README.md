# FPGA Tactical Controller for StarCraft II Micro Scenarios

EECS 3216 course project targeting the Terasic DE10-Lite FPGA board, Fall 2026.
Target difficulty: **Tier A, subject to instructor approval**.

The FPGA receives a combat snapshot over UART, evaluates a small squad's strength,
selects advance/attack/retreat/hold behavior, and allocates attack targets. A PC
adapter translates observations and commands through the StarCraft II API. SC2
simulates and renders the game; the FPGA's VGA output is a simple top-down status
diagram with colored unit markers, target/waypoint highlights, and state text.

## Current status

**Planning scaffold only.** No HDL, host adapter, working Quartus project, or
automated simulation suite has been implemented. Map/client compatibility,
benchmark behavior, resource utilization, timing, and gameplay benefit are
unverified. This repository does not run SC2 or program a board yet.

## Start here

- [Current proposal (PDF)](docs/proposal/proposal.pdf)
- [Editable proposal (LaTeX)](docs/proposal/proposal.tex)
- [Implementation plan and team responsibilities](docs/implementation-plan.md)
- [Architecture and draft interface decisions](docs/architecture.md)
- [Risks and responses](docs/risks.md)
- [Intended demonstration](docs/demo.md)
- [Research, SDK, map, and hardware references](docs/references.md)
- [Contribution workflow](CONTRIBUTING.md)

## Required scope

- DE10-Lite MAX 10 `10M50DAF484C7G`, custom SystemVerilog logic.
- Custom UART RX/TX and framed packet handling, initially 115,200 baud, 8-N-1.
- On-chip record memory, a four-stage distance/ranking pipeline, strength
  assessment, tactical FSM, and per-snapshot damage reservations.
- Capacity of 0–16 friendly and enemy unit records per side; initial SC2 demos
  use 4–8 Marines against 4–8 Zerglings on open terrain without upgrades/abilities.
- Advance, attack, retreat, and hold behavior, with authored objective/safety waypoints.
- Required SC2 integration in single-step mode. Continuous real-time operation
  is a later experiment, not an initial acceptance requirement.
- Schematic VGA status output, HEX diagnostics, and board controls.
- Independent software-reference checks and matched gameplay comparisons.

The initial strength score and retreat cutoffs are engineering hypotheses, not
validated combat laws. Correct hardware behavior is required; speedup and improved
win rate must be measured rather than assumed.

## Repository layout

```text
rtl/            Planned SystemVerilog modules
sim/            Planned HDL testbenches and reference-vector exchange
host/           Planned SC2 adapter and independent software reference
quartus/        Planned board project, timing constraints, and pin assignments
scenarios/      Scenario definitions, map qualification, and benchmark setup
docs/           Proposal, implementation plan, architecture, risks, demo, references
.github/        Issue and pull-request templates
```

The component READMEs describe planned work; they are not build instructions for
an existing implementation. Add actual commands and selected tool versions when
each component becomes executable.

## Course milestones

- Proposal: **November 13, 2026, 23:59**.
- In-person demonstration: **December 2, 2026, 16:00–18:50**.
- Final report and code submission: **December 2, 2026, 23:59**.

See the implementation plan for the proposed internal schedule. Team names,
student numbers, workstream owners, and the first tested map/client versions
remain to be filled in. Put student numbers in submission copies as appropriate.

## Third-party material and license

The proposed original work is the HDL, adapter integration, reference tests, and
scenario evaluation. Credit reused algorithms, SDK/example code, maps, and IP
separately; see [references](docs/references.md). Download game clients, maps, and
SDK dependencies through their upstream distribution channels.

A license for the team's original code has not been selected. No third-party
source or game assets are vendored in this scaffold.
