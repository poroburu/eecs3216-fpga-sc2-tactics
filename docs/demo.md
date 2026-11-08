# Demo runbook

About 8 minutes. Everything below has been run on our PC and board. Read
[how-it-works.md](how-it-works.md) first; it is the explanation to give.

## Equipment

- A PC with WSL2, Quartus Prime Lite 25.1std, the Linux SC2 4.10 client in `~/StarCraftII`,
  and the Windows SC2 client.
- DE10-Lite on the USB-Blaster.
- FT232R USB-UART adapter (COM5), set to **3.3 V**, wired as:
  - adapter TXD → `GPIO[0]` (header pin 1)
  - adapter RXD → `GPIO[1]` (header pin 2)
  - GND → GND
- VGA monitor on the DE10-Lite VGA port. **Not yet tried on a real monitor**: only the
  simulated frame and its 16.8 ms frame period have been checked.

## 10 minutes before

```bash
cd <repo>
tools/demo.sh preflight     # USB-Blaster + 10M50DA, COM5, both SC2 installs, Python env, bitstream
tools/demo.sh program       # the bitstream is volatile: reprogram after every power-cycle
tools/demo.sh check         # expect "RESULT PASS 1216/1216" (~20 s)
```

`check` is a dry run, not part of the demo. It pushes about 60 frames a second, so the
VGA and HEX flicker too fast to follow. Keep its last lines on screen to quote in step 5.

Set `SW0` down (CLOSEST), `SW4..1` all down, and press `KEY0` once.

If the bitstream is missing, run `tools/demo.sh build` first (about 45 s). If the Python
environment is missing:

```bash
uv venv host/.venv && VIRTUAL_ENV=host/.venv uv pip install -r host/requirements.txt
```

## Script

### 1. The boundary (1 min)

Show the board, the adapter wires, and the VGA monitor.

> "SC2 simulates the fight. The PC only translates. The FPGA decides which enemy each
> Marine shoots. `SW0` chooses between two exactly specified rules."

Open [protocol.md](protocol.md) at "The rule" and point at the four-line key definition.

### 2. Live game, CLOSEST (2.5 min)

```bash
tools/demo.sh watch          # visible SC2 window at normal speed; Ctrl-C to stop early
```

- The terminal prints every decision: Roach HP → the FPGA's target list, round-trip time,
  and FPGA clock cycles.
- On VGA, the banner is cyan. Each Marine has a dimmed line to the Roach it is shooting,
  and the lines fan out across several Roaches. `LEDR9..4` shows several distinct targets.
- Use `SW4..1` to pick a Marine; `HEX0` shows its current target.

### 3. Flip SW0 to FOCUS during the game (2.5 min)

- `HEX3` changes `C` → `F` and the banner turns orange.
- The lines from Marines in range swing onto the weakest Roach, and the `LEDR` bar shrinks.
- The terminal's policy column changes to `FOCUS`. No software was touched.

> "Same game, same PC code. The only change is one switch on the FPGA."

### 4. Matched comparison (1 min)

Real-time games are not repeatable, so the fair comparison uses fixed seeds in step mode:

```bash
tools/demo.sh compare 5      # headless, ~7 s per game, uses the current SW0
```

Run it once with `SW0` down and once up. The reference numbers over seeds 1–10 are
CLOSEST 32.1 and FOCUS 62.4 ([results.md](results.md)). Five games give a smaller sample.

### 5. Verification, resources, and the dry run (1 min)

Say what the dry run proved: 1,216 frames over the real UART, every byte matching the
independent reference, in both Verilator and Questa. Then point at the Quartus figures in
[results.md](results.md): 15,847 LEs, 4,194 registers, 68 embedded 9-bit multiplier
elements, +4.283 ns setup slack at 50 MHz.

## If something fails

| Symptom | Do |
|---|---|
| `check` fails with link errors | Check the three adapter wires and the 3.3 V jumper, then reprogram |
| Everything on HEX is dark | The board was power-cycled: run `tools/demo.sh program` |
| SC2 window never opens | `powershell.exe "Get-Process SC2_x64 \| Stop-Process"`, then retry. Headless still works: `host/.venv/bin/python host/sc2_demo.py --port win:COM5` |
| No board at all | `tools/demo.sh model 1` runs the same game with the Python reference. Say clearly that this is the software reference, not the FPGA. |

## Not yet demonstrated

- The target lines on the real monitor. The markers and banner were seen working on November 8.
- `hw_check` with `SW0` up. Only CLOSEST has been checked on the board, because the
  switch has to be flipped by hand. FOCUS cases (directed, SC2 traces, and about half the random set) pass in simulation.
- A full game where `SW0` is flipped partway through.
