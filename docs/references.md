# References and third-party boundaries

Updated November 12, 2026. The assessed draft is based on
[PR #6](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/pull/6), commit
`7ce3b0e924949c3fc2966cbacd9eeae0be07a2f2`, especially `docs/results.md`,
`docs/protocol.md`, `docs/how-it-works.md`, `docs/scoping-exploration.md`,
`rtl/target_select.sv` and `host/sc2fpga/reference.py`.
That PR records actual target-selector/board results; the new Lanchester guard
is proposed. Historical AI Arena/MarineMicroBot references below are background,
not dependencies of the updated demo.

These sources support the design rationale. They do not establish that the
hardware is implemented, faster than software, or better at winning fights.
No private textbook contents or unrelated project internals are included here.

## Game control and target allocation

1. **Ian Millington, AI for Games, third edition, 2019.** Section 5.3,
   printed pages 314–317, describes state-based game behaviors and guarded
   transitions. This informs the tactical FSM; exact states/thresholds are our
   design choices. ISBN 978-1-138-48397-2.
2. **David Churchill and Michael Buro, Portfolio Greedy Search and Simulation
   for Large-Scale Combat in StarCraft, 2013.** Sections II–III describe an
   abstract combat model, attack/move/wait actions, weakest-target scripts, and
   no-overkill damage assignments. Our weakest-first reservation rule is an
   adaptation of those ideas, not an implementation of full portfolio search.
   [Author's paper](https://davechurchill.ca/publications/pdf/combat13.pdf).
3. **Edward A. Lee and Sanjit A. Seshia, Introduction to Embedded Systems:
   A Cyber-Physical Systems Approach, second edition, MIT Press, 2017.**
   **Figure 1.1, printed p. 6 (PDF p. 26),** supplies the physical plant,
   sensors/actuators, computing platforms and network-fabric vocabulary used in
   our adapted feedback diagram. SC2 substitutes for the physical plant; its
   observation/action APIs substitute for physical sensing/actuation.
   Section 3.3 discusses guarded FSM reactions; printed pages 50–53 include
   reaction timing and hysteresis. This informs explicit state/transition
   semantics. [Author-hosted version 2.3](https://ptolemy.berkeley.edu/books/leeseshia/releases/LeeSeshia_DigitalV2_3.pdf).
4. **Benjamin Ellis et al., SMACv2: An Improved Benchmark for Cooperative
   Multi-Agent Reinforcement Learning, 2023.** The benchmark critique motivates
   varying starting conditions to verify observation-dependent behavior.
   It does not require us to implement learning or adopt the SMACv2 stack.
   [Paper, version 2](https://arxiv.org/abs/2212.07489v2).

5. **Marius Stanescu, Nicolas Barriga and Michael Buro, Using Lanchester Attrition
   Laws for Combat Prediction in StarCraft, AIIDE, 2015.** Supports considering
   attrition models for engagement decisions. Our proposed `k*N²` guard uses
   fixed matchup coefficients and is not the paper's fitted/extended predictor.
   [Publisher PDF](https://cdn.aaai.org/ojs/12780/12780-52-16297-1-2-20201228.pdf).

The previous `sum(health * damage_per_attack)` score and two-to-one cutoff are
superseded in the updated draft. The proposed square-law guard, 0.75 strength
cutoff, quarter-health cutoff and retreat latch are engineering choices to
validate, not constants established by these works.

## SC2 host and comparator

The actual PR #6 host uses **burnysc2 7.3.0** and pyserial, not the earlier
C++/MarineMicroBot plan. See [burnysc2 source](https://github.com/BurnySc2/python-sc2)
and preserve its notices if reusing code. Current paired controls are CLOSEST
and FOCUS on the same board/map, not a port of an external bot.

- [Blizzard s2client-api](https://github.com/Blizzard/s2client-api): C++ API and
  examples, pinned at `third_party/s2client-api` for the optional
  [Linux launch/observe/step smoke test](sc2-linux.md). The SDK is third-party
  code, not an original HDL contribution.
- [MarineMicroBot source](https://github.com/Blizzard/s2client-api/blob/master/examples/common/bot_examples.cc):
  the original proposal's comparator for Marines versus Zerglings, now deferred.
  This is an example controller, not a complete competitive bot.
- [SC2 protocol](https://github.com/Blizzard/s2client-proto/blob/master/docs/protocol.md):
  observation/action interface and single-step mode.
- [cpp-sc2 CommandCenter](https://github.com/cpp-sc2/commandcenter): possible
  later comparator with combat micro-controllers. It requires qualification and
  adaptation for fixed-army scenarios; it is not a required benchmark yet.

Preserve upstream notices when reusing source. Pin the actual host/library/client
revisions with every new result; the PR's recorded versions are not automatically
the versions used for a later extension.

## Maps

The updated scope uses Blizzard **DefeatRoaches** mini-game assets, distributed
separately ([Blizzard's SC2 Learning Environment](https://github.com/google-deepmind/pysc2#mini-games)).
Record actual map bytes/hash and client revisions with results; do not redistribute
the game assets. AI Arena qualification below belongs to the original plan.

- [AI Arena map downloads](https://aiarena.net/wiki/maps/).
- [AI Arena micro-map source](https://github.com/aiarena/micro-ladder-maps).

AI Arena compatibility with the supported matchup is not established and is no
longer required. Any future map change needs spawn/reset/terrain/count/client
qualification. Map assets are external work, not part of the originality claim.

## Hardware and tools

- [Terasic DE10-Lite specifications](https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=218&Language=English&No=1021&PartNo=2):
  target device, on-chip resources, GPIO/VGA, and external memory.
- Terasic DE10-Lite User Manual: pin assignments and board timing references;
  record the manual revision used when creating the Quartus project.
- PR #6 uses no PLL IP and holds records in registers, with embedded multipliers
  for distance and VGA line arithmetic. Recheck resource/timing reports after
  extensions; do not reuse the old RAM/PLL plan as an implemented feature.

## Attribution practice

Credit algorithms, copied/adapted code, generated IP, and maps separately.
Original hardware implementation does not imply the underlying algorithm is new.
This checkout contains the updated proposal and earlier UART diagnostic with a
pinned upstream SDK. The game demo and its detailed test records are in PR #6. Game clients, maps
and textbook chapters are not redistributed with this draft.
