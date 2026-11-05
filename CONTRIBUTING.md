# Working together

Start with the [implementation plan](docs/implementation-plan.md) and
[architecture](docs/architecture.md). There is no implementation to build yet;
the first milestone is a working software-controlled SC2 scenario and a tested
map/client/API combination.

## Small, reviewable changes

1. Open an issue using the work-item template. State the behavior, owner,
   acceptance criteria, and dependencies.
2. Create a branch, for example `feat/uart-rx`, `feat/sc2-observations`, or
   `docs/packet-contract`.
3. Keep the change focused on one subsystem or a clearly described integration.
4. Open a pull request and ask another team member to review it.
5. Include the verification actually performed and unresolved limitations.
6. Merge after review and any configured checks pass.

Use the numbered Student 1–4 workstreams until actual owners are assigned.
Interface changes need agreement from both producer and consumer owners before
dependent implementations are merged.

## Verification by change type

- HDL: meaningful ModelSim testbenches, known-answer and boundary cases; include
  the exact command/tool version once available.
- Datapath/control: compare outputs with an independently written fixed-point
  reference. Do not generate expected results by replaying the HDL's outputs.
- Host/scenario: verify actual commands, unit IDs, round boundaries, and map/client
  compatibility. Mocked tests do not establish a working SC2 integration.
- Quartus: record device selection, pin constraints, resource reports, and timing.
- Gameplay: preserve the scenario, selected policy revisions, opponent, seed where
  supported, step interval, outcomes, and failed/invalid runs.
- Documentation: check links, scope consistency, and the proposal's one-page limit.

Use deterministic tie-breaking. Separate per-snapshot estimated damage from
confirmed game damage. Do not claim a build, test, win-rate improvement, or speedup
without the corresponding result.

## Source control

Commit first-party source, constraints, testbenches, scenario definitions, and
small reproducible fixtures. Keep generated Quartus databases, waveforms, local
game installations, credentials, and downloaded dependency trees out of Git.
Preserve the current proposal PDF alongside its LaTeX source.

The template does not yet contain student names/numbers. Coordinate public author
credits and the license for original code as a group.

## Suggested repository setting

After the initial scaffold is published, protect `main` and require one approving
review. That setting is a recommendation here; it has not been configured by
this scaffold.
