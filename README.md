# FPGA Tactical Controller for StarCraft II Micro Scenarios

EECS 3216 course project, Fall 2026, Terasic DE10-Lite MAX 10.
Target: **Tier A, subject to instructor approval**.

The FPGA chooses attack targets in StarCraft II's **DefeatRoaches** mini-game.
A physical switch selects nearest-target or weakest-in-range focus fire; VGA
shows unit markers and target lines. A PC transports observations and applies
the returned orders. SC2 handles movement, pathing and combat.

## Status and updated proposal

The working FPGA-in-the-loop demo is included in this checkout. Start with
[how it works](docs/how-it-works.md) and the [executable runbook](docs/demo-runbook.md):
`tools/demo.sh preflight | program | check | watch | compare`.
[Recorded results](docs/results.md) describe the November 8 baseline. The
[November 12 operating runbook](docs/runbook.md) records the tested custom
Windows/WSL launch, Linux operation, and 1,216 passing board FOCUS cases. Matched
board FOCUS comparison evidence remains outstanding.

The project lead reports provisional TA approval of the demo and completed the
implementation to date. The updated draft preserves the working comparison and
proposes one extension: a bounded Lanchester-inspired strength guard selecting
ATTACK/RETREAT/HOLD, with strength bars/state/reason on VGA. The extension and
Tier A assessment require course approval; the strength guard and tactical-state extension remain unimplemented.

- [Updated one-page proposal PDF](docs/proposal/proposal.pdf)
- [Editable proposal](docs/proposal/proposal.tex)
- [Algorithm shortlist and scope rationale](docs/proposal/scope.md)
- [CPS feedback architecture](docs/architecture.md)
- [Schedule and realistic team allocation](docs/implementation-plan.md)
- [Eight-minute demo presentation](docs/demo.md)
- [Earlier diagnostic protocol](docs/diagnostic-protocol.md), [bring-up](docs/uart-bringup.md),
  [verification](docs/verification.md), and [Linux SDK smoke test](docs/sc2-linux.md)
- [Risks](docs/risks.md), [references](docs/references.md),
  [contribution workflow](CONTRIBUTING.md)

Retained PR evidence distinguishes board CLOSEST results from software FOCUS
results. Record matched board trials under both switches before claiming a
reproducible hardware outcome improvement. Core cycle predictability, concurrent
I/O/video and reference-matching outputs are the hardware demonstration; no
end-to-end CPU speedup is assumed.

## Scope

- DE10-Lite `10M50DAF484C7G`, custom SystemVerilog, 50 MHz processing clock.
- Custom UART RX/TX and parser/reply FSMs, 115200 baud, 8-N-1.
- Up to 16 records/side; Marine/Roach matchup, fixed integer ranking and ties.
- Three-stage distance/ranking pipeline, register records and VGA/HEX/LED output.
- Step-mode evaluation, eight game loops per decision; real-time mode is
  supplementary. SC2 native auto-targeting may occur between decisions.
- Versioned protocol/HP/reset/movement additions for the planned strength guard;
  one safe waypoint, no general path planning. Integration gate November 20.
- Defer mixed armies, spells, learning, search, reservations, kiting and external
  bot/map qualification. See the scope note for rationale and acceptance.

## Repository layout

- `rtl/`: demo UART, parser, target pipeline, reply, VGA and top level.
- `host/sc2fpga/`, `host/sc2_demo.py`: game adapter and independent demo reference.
- `sim/`: demo system tests and the earlier diagnostic's host/RTL tests.
- `quartus/sc2fpga/`: demo build; `quartus/uart_diagnostic.qpf`: earlier diagnostic.
- `rtl/diagnostic/`, `host/protocol.py`, `host/transport.py`: earlier transport
  contract, separate from the demo. These hosts/bitstreams are incompatible.
- `third_party/s2client-api`: optional pinned C++ Linux smoke-test SDK.
- `docs/`: proposal, architecture, runbook, evidence, risks and team plan.

Run `sim/run_verilator.sh` for the demo. For the earlier diagnostic run
`python3 -m unittest discover -s sim -p 'test_*.py' -v` and
`python3 sim/run_rtl.py` with Icarus Verilog 12. The diagnostic still returns
UNSUPPORTED for tactical requests; it is not the demo controller. Reusable new
scripts belong in `scripts/`; existing demo `tools/` paths are preserved.

## Course dates and credits

Proposal: **November 13, 2026, 23:59**. Live demo: **December 2, 16:00–18:50**.
Final report/code: **December 2, 23:59**. Team names/IDs remain to be filled in.

Credit algorithm sources, SDK/library code, map assets and generated IP separately
from the team's implementation. See [references](docs/references.md). A license
for original code has not been selected; no game clients/assets are vendored here.
