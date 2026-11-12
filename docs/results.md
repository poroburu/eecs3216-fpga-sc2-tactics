# Measured results — November 8, 2026

| Item | Version |
|---|---|
| Source | this repository at the commit that adds this file |
| Board | DE10-Lite (JTAG id `031050DD`, 10M50DA), USB-Blaster |
| UART adapter | FTDI FT232R USB-UART (`0403:6001`), COM5 |
| Quartus | Prime Lite 25.1std |
| Simulators | Verilator 5.054 and Questa FSE (Quartus 25.1std), same testbench |
| Game clients | SC2 Linux 4.10.0 (Base75689, headless) and Windows Base97563 (window) |
| SC2 API library | burnysc2 7.3.0 |

## Synthesis (Quartus, `quartus/sc2fpga`)

| Resource | Used |
|---|---|
| Logic elements | 15,847 / 49,760 (32 %); about 9,200 of these draw the target lines |
| Registers | 4,194 |
| Embedded multiplier 9-bit elements | 68 / 288 (4 for distances, 64 for 16 VGA target lines) |
| Memory bits | 0 (unit records are held in registers so the VGA renderer can read all 32 in parallel) |
| PLLs | 0 (VGA uses a 25 MHz pixel enable from the 50 MHz clock) |
| Pins | 121 / 360 |
| Timing, slow 85 °C model, 50 MHz | setup slack +4.283 ns; worst hold slack +0.109 ns (fast model); no failing paths |

## Correctness

Every result below is a byte-for-byte match of the full reply, including cycle count and
checksum, against `host/sc2fpga/reference.py`.

| Set | Verilator and Questa (through the UART pins) | Board over COM5 (`SW0` = CLOSEST) |
|---|---|---|
| Directed (34): ties, empty sets, range boundary, max coordinates, 16×16, all error codes, recovery | 34 / 34 | 34 / 34 |
| SC2 trace (182): 91 recorded snapshots × 2 policies | 182 / 182 | 182 / 182 |
| Random (1,000): 515 with FOCUS in simulation | 1000 / 1000 | 1000 / 1000 |
| Mutation check: one corrupted expected byte | detected | n/a |

The VGA frame period in simulation is 16,800,000 ns, exactly 800 × 525 × 2 clocks
(59.52 Hz). The simulated frames are in `docs/img/`.

## Timing on the link

| Measure | Value |
|---|---|
| FPGA compute | `nF·nE + 2` clocks. 9 Marines × 4 Roaches = 38 clocks = 0.76 µs. Maximum 258 clocks = 5.16 µs |
| Round trip, PC → board → PC, through the PowerShell bridge | median 15.9 ms, p95 19.5 ms, max 34.6 ms (1,216 frames) |
| Real-time game, visible client | 52 decisions in a 28 s game, 0 link errors, median 16.7 ms |

The round trip is dominated by UART bytes (a 9 + 4 frame is 63 bytes, 5.5 ms) and USB and
bridge latency. It is not FPGA compute.

## Gameplay: DefeatRoaches, step mode, 8 loops per decision, seeds 1–10

| Controller | Score per seed (1–10) | Mean |
|---|---|---|
| **Board, SW0 = CLOSEST** | 12 72 37 12 13 12 22 22 72 47 | **32.1** |
| Python reference, CLOSEST (exploration sweep) | 12 72 37 12 13 12 22 22 72 47 | 32.1 |
| Python reference, FOCUS | see `explore/results/defeatroaches_sweep.jsonl` | 62.4 |

The board matched the reference **game for game**, including game length and order
count. Board runs with `SW0` = FOCUS are still to be recorded: flip the switch and run
`tools/demo.sh compare 10`.

## Known warnings and limits

- Quartus warnings are expected ones: the input-only UART RX pin, permanently enabled
  UART TX, unused `SW9..5`, decimal-point segments tied off, and a LogicLock licence
  notice. There are no critical warnings and no latches.
- Questa FSE needs the free Questa Starter licence generated for this PC's network adapter
  (fixed-node). Point the Windows user variable `SALT_LICENSE_SERVER` at the licence file.
  A licence made for an adapter the PC no longer has fails at checkout.
- `sc2_demo.py` caps snapshots at 16 units per side. DefeatRoaches never exceeded 10 Marines
  or 4 Roaches, and any capping is counted in `truncated_steps`.
