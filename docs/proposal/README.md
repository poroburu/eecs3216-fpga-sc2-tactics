# Updated proposal draft

- [One-page PDF](proposal.pdf)
- [Editable LaTeX](proposal.tex)
- [Algorithm shortlist, scope and rationale](scope.md)
- [Architecture adapted from textbook Figure 1.1](../architecture.md)
- [Standalone architecture visual](architecture.html)
- [Realistic team allocation](../implementation-plan.md)
- [Eight-minute demo plan](../demo.md)

Title: **FPGA Tactical Controller for StarCraft II Micro Scenarios**.
Updated November 12, 2026, using the working Marine/Roach demo in
[PR #6](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/pull/6).
The lead reports provisional TA approval of the existing demo. Tier A and the
proposed Lanchester/retreat extension remain subject to course approval.
Names/student IDs are placeholders; the lead's completed implementation is
distinguished from future partner deliverables.

This replaces the original AI Arena/MarineMicroBot plan. Required foundation:
physical CLOSEST/FOCUS toggle, verified target pipeline, live SC2 and VGA.
Planned extension: a bounded Lanchester-inspired strength guard with explicit
ATTACK/RETREAT/HOLD behavior. Reservations and kiting are deferred.

The one-page draft emphasizes the project goal, visible tactical decisions and
hardware contribution, using short paragraphs and separate role bullets.
Detailed thresholds, measurement evidence and reproducibility requirements
remain in [the supporting scope note](scope.md).

Keep LaTeX and PDF together. Compile with a standard LaTeX distribution:

```bash
cd docs/proposal
pdflatex -interaction=nonstopmode -halt-on-error proposal.tex
```

Alternatively, `tectonic --keep-logs docs/proposal/proposal.tex` from the root.
The draft was built with Tectonic 0.17.0 and checked for one page, overflow and
visual layout. A compiler is not bundled. Inspect after edits; add names/IDs to
the course submission copy in accordance with the team's author-credit choice.
