# References and third-party boundaries

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
   Section 3.3 discusses guarded FSM reactions; printed pages 50–53 include
   reaction timing and hysteresis. This informs explicit state/transition
   semantics. [Author-hosted version 2.3](https://ptolemy.berkeley.edu/books/leeseshia/releases/LeeSeshia_DigitalV2_3.pdf).
4. **Benjamin Ellis et al., SMACv2: An Improved Benchmark for Cooperative
   Multi-Agent Reinforcement Learning, 2023.** The benchmark critique motivates
   varying starting conditions to verify observation-dependent behavior.
   It does not require us to implement learning or adopt the SMACv2 stack.
   [Paper, version 2](https://arxiv.org/abs/2212.07489v2).

The score `sum(health * damage_per_attack)`, two-to-one strength cutoff,
quarter-health cutoff, and latched retreat are baseline engineering choices
to test. These exact choices are not validated by the works above.

## SC2 host and comparator

- [Blizzard s2client-api](https://github.com/Blizzard/s2client-api): C++ API and
  examples, now pinned as `third_party/s2client-api`. The SDK is third-party code,
  not an original HDL contribution. See [Linux setup](sc2-linux.md) for revision,
  upstream headless download links and the executable smoke check.
- [MarineMicroBot source](https://github.com/Blizzard/s2client-api/blob/master/examples/common/bot_examples.cc):
  first named open-source comparison policy for Marines versus Zerglings.
  Pin the revision and document any scenario/host adaptation. This is a small
  example micro-controller, not a complete competitive bot.
- [SC2 protocol](https://github.com/Blizzard/s2client-proto/blob/master/docs/protocol.md):
  observation/action interface and single-step mode.
- [cpp-sc2 CommandCenter](https://github.com/cpp-sc2/commandcenter): possible
  later comparator with combat micro-controllers. It requires qualification and
  adaptation for fixed-army scenarios; it is not a required benchmark yet.

Preserve upstream notices when reusing source. The initial UART host uses
Python 3.12 and pySerial 3.5; the SC2 API/library binding and comparator
revisions still require a qualified smoke test.

## Maps

- [AI Arena map downloads](https://aiarena.net/wiki/maps/).
- [AI Arena micro-map source](https://github.com/aiarena/micro-ladder-maps).

Availability is verified; compatibility with our host and supported matchup is
not. Select/adapt rounds after checking actual spawns, reset behavior, terrain,
unit counts, and client support. Record original map identity and any modifications.
Map assets are external work, not part of the group's originality claim.

## Hardware and tools

- [Terasic DE10-Lite specifications](https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=218&Language=English&No=1021&PartNo=2):
  target device, on-chip resources, GPIO/VGA, and external memory.
- Terasic DE10-Lite User Manual: pin assignments and board timing references;
  record the manual revision used when creating the Quartus project.
- Quartus PLL IP is planned; record generated parameters and tool version.
  RAM/multiplier inference and fitting must be checked in actual synthesis reports.

## Attribution practice

Credit algorithms, copied/adapted code, generated IP, and maps separately.
Original hardware implementation does not imply the underlying algorithm is new.
The repository contains original implementation/planning documents and a pinned
upstream SDK submodule. Game clients/data, external maps and textbook chapters
are not redistributed in this project.
