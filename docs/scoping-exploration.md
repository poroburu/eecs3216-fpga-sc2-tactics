# Scoping exploration — November 8, 2026

The instructor's concern with the current proposal: it may be **too difficult**
or **impossible to define exhaustively**. This exploration checked what the
actual lab machine can do and asked one question: can the FPGA's job be reduced
to a *closed specification*, where every legal input has exactly one correct
output, and still keep SC2 as a convincing demonstration?

Short answer: **yes.** Recommended rescope is at the end.

## What was verified on this machine

All results come from the commands and scripts in [`explore/`](../explore/README.md).

| Item | Result |
|---|---|
| SC2 headless (Linux) | Linux client **4.10.0 (Base75689)** in `~/StarCraftII` runs headless from WSL2 with `burnysc2==7.3.0`. Required `SC2_WSL_DETECT=0`; otherwise the library tries to launch the Windows client. |
| Maps | The Blizzard mini-games (`DefeatRoaches`, `DefeatZerglingsAndBanelings`, `FindAndDefeatZerglings`, …) and the `Flat*`/`Simple*` maps are installed. AI Arena maps were **not** needed. |
| Episode cost | One DefeatRoaches episode (launch + play + exit) takes about 6.5 s of wall-clock time in non-realtime single-step mode. |
| Determinism | Same map + seed + policy gave identical score, final game loop, and order count across repeated runs (seed 1, `focus`: 37 / 640 / 58 both times). |
| JTAG | `jtagconfig.exe`: `USB-Blaster [USB-0]` → `031050DD 10M50DA`. |
| Quartus | Quartus Prime Lite **25.1std** (Windows) compiles a project for `10M50DAF484C7G` when called from WSL. A UART echo probe fits in **93 LEs, 67 registers, Fmax 229.89 MHz** (slow 85 °C model). |
| UART adapter | The FTDI FT232R (`0403:6001`) is **COM5** on Windows and opens at 115200 8-N-1. It is *not* visible inside WSL (not attached with `usbipd`). |
| Not verified | Which DE10-Lite GPIO pins the FTDI is wired to, whether the adapter is set to 3.3 V, and a real board-to-PC echo. The probe uses `ARDUINO_IO[0]=PIN_AB5` (RX) and `ARDUINO_IO[1]=PIN_AB6` (TX) as **placeholders**. The board was not programmed during this exploration. |

## Experiment: does a small, exactly specified rule matter in-game?

`explore/sc2/experiment.py` runs the `DefeatRoaches` mini-game: 9 Marines
against waves of 4 Roaches on flat ground, one unit type per side, no
abilities. On every decision (`game_step = 8` loops ≈ 0.36 s of game time),
it calls a pure integer function `decide(friend[], enemy[])`. That function has
the shape an FPGA would compute:

- positions in Q.4 fixed point (1/16 map unit);
- squared distance compared against a precomputed `reach²`;
- a lexicographic minimum per friendly unit.

| Policy (exact rule) | Mean score (10 seeds) | Min–max | Mean episode length |
|---|---|---|---|
| `closest` — key `(d², j)` | **32.1** | 12–72 | 567 loops |
| `focus` — key `(out_of_range, hp_remaining_if_in_range, d², j)` | **62.4** | 37–107 | 874 loops |
| `focus_nooverkill` — `focus` + per-snapshot damage reservation | **61.4** | 22–107 | 847 loops |

Observations:

- Swapping one comparison key **roughly doubles the score**. A visible, repeatable
  in-game difference does not need a strength model, retreat logic, or waypoints.
- Damage reservations (the "no overkill" idea in the current proposal) gave
  **no benefit** at this decision interval. They add memory hazards and ordering
  rules, so they are good candidates to cut.
- Observed bounds over all runs: at most **10 friendly** and **4 enemy** units;
  x, y ≤ 670 in Q.4 (fits 11 bits); enemy HP ≤ 145 (8 bits); `reach² = 8836`
  (14 bits); `d²` < 2²¹.
- Software decision time was 6–8 µs per call in Python. Compute speed is not the
  argument for the FPGA; the argument is a verified hardware implementation of
  a specified function.

### UART budget

The data is about 4 bytes per unit (x, y, hp, ready). A 16 + 16 unit snapshot
is about 130 bytes with framing, which takes about **11 ms** at 115200 baud. One
decision interval at normal game speed is about **357 ms**. Single-step mode is
therefore easy. Real-time play is plausible later but stays optional.

## Why the current proposal is hard to define

| Current element | Problem for an exhaustive spec |
|---|---|
| Strength score `Σ health·damage` + 2:1 / 25 % retreat cutoffs | A heuristic with no "correct" answer. The only way to judge it is win rate, which is not a hardware property. |
| Advance / attack / retreat / hold FSM with authored waypoints | Behavior depends on SC2 pathing, cooldown timing, and map geometry outside the FPGA. |
| Per-snapshot damage reservations | Order-dependent state. Shown above to add nothing at this interval. |
| AI Arena maps + MarineMicroBot comparator | External qualification work: client versions, map adaptation, porting a C++ bot. None of it is graded hardware. |
| 0–16 records of unspecified type, open-ended "SC2 integration" | The input domain is not pinned down. |

## Recommended rescope

**Working title:** *UART-Connected Target-Allocation Coprocessor with VGA
Status Display, Demonstrated in an SC2 Mini-Game*.

### The closed specification (the whole FPGA contract)

- **Input frame:** `snap_id`, `nF ≤ 16`, `nE ≤ 16`, and for each unit
  `x, y` (unsigned 11-bit Q.4), `hp` (8-bit), and `ready` (1 bit, friendly
  only). Scenario constants are `reach²` (16-bit) and `policy` (from `SW0`, or
  from a frame field).
- **Output frame:** `snap_id`, `status`, `target[i]` ∈ {0…nE−1, NONE} for
  each friendly unit, and the cycle count.
- **Rule:** for each friendly unit `i`, `target[i] = argmin_j key(i, j)`, with
  `d² = (xi−xj)² + (yi−yj)²`:
  - `policy=0` (closest): `key = (d², j)`.
  - `policy=1` (focus): `key = (d² > reach², d² ≤ reach² ? hp_j : 0, d², j)`.
  - When `nE = 0`, the output is NONE.
- **Errors:** bad checksum, a count > 16, an out-of-range field, or an
  inter-byte timeout each produce an error reply and HEX code. A partial frame
  never changes the outputs.

This is a pure function over a bounded, enumerable domain. Every input has
exactly one correct output, and a ~30-line software reference (`decide()` in
`experiment.py`) defines it. "Correct" becomes a **bit-exact match** to that
reference, not a judgement about tactics.

### What stays (Tier A justification)

- Custom UART RX/TX with baud generator, framing, checksum, and timeout.
  "Implementing USB or UART communication interfaces" is an explicit Tier A
  example in the course instructions.
- A control FSM: `IDLE, RECEIVE, VALIDATE, COMPUTE, REPLY, ERROR`.
- An on-chip record RAM (M9K).
- A pipelined distance unit: subtract → square (embedded multipliers) → compare.
- A lexicographic comparator/argmin unit.
- A 640×480 VGA schematic of unit markers and target lines with a PLL pixel
  clock, plus a clock-domain crossing of the display snapshot.
- HEX/LED diagnostics.

### What is cut or deferred

The strength estimate, retreat/advance/hold FSM, waypoints, damage
reservations, AI Arena maps, the MarineMicroBot comparator, mixed unit types,
and real-time play.

### Demo with built-in A/B

`SW0` switches the *FPGA* between `closest` and `focus`. That gives a live A/B
comparison on the same board, map, and seed, with no external comparator to
qualify. Software preview: 32.1 vs 62.4 mean score over 10 seeds. That number is
evidence the effect is visible, **not** a promised result.

### Verification that cannot be ambiguous

1. **ModelSim:** directed corner cases (ties, `nE = 0`, all out of range,
   `d² == reach²`, max coordinates, max counts), randomized frames, and
   **recorded real SC2 snapshots** (`explore/results/trace_focus_seed3.jsonl`
   has 91) checked against the software reference.
2. **On hardware:** the host replays recorded snapshots over UART and checks
   every reply bit-exactly. This does not need SC2 at all.
3. **Live:** SC2 DefeatRoaches in single-step mode with the FPGA in the loop,
   with outcomes logged per seed for both `SW0` settings.

Step 2 is the fallback that protects the grade: if SC2 integration slips, the
hardware can still be fully demonstrated and verified.

### Optional stretch (only after core passes)

- `DefeatZerglingsAndBanelings`: 9 Marines vs 6 Zerglings + 4 Banelings, which
  needs a per-type priority field.
- Real-time mode.
- A 1–2 field priority extension, for example "prefer the target already being
  attacked".

## Open items before the proposal

1. Confirm the FTDI-to-GPIO wiring and the 3.3 V setting, then program
   `explore/quartus-uart-probe` and check a real echo on COM5.
2. Decide the serial path for the host: `usbipd bind` + `attach` the FTDI into
   WSL (one-time admin step; it then appears as `/dev/ttyUSB0`), or run a small
   relay on Windows Python.
3. Bring this rescope to the instructor or a TA before rewriting `proposal.tex`.
