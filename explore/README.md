# Exploration scripts (November 8, 2026)

These are throwaway probes behind [docs/scoping-exploration.md](../docs/scoping-exploration.md).
They are not the project implementation.

## SC2 (WSL2, Linux client 4.10 / Base75689)

```bash
uv venv venv && VIRTUAL_ENV=$PWD/venv uv pip install burnysc2==7.3.0
export SC2_WSL_DETECT=0 SC2PATH=$HOME/StarCraftII   # force the Linux client under WSL
venv/bin/python explore/sc2/probe.py DefeatRoaches 1500          # unit stats, attack-closest
venv/bin/python explore/sc2/experiment.py DefeatRoaches focus 1 8 out.jsonl [trace.jsonl]
#                                          MAP          POLICY SEED GAME_STEP
```

Policies are `closest`, `focus`, and `focus_nooverkill`. `decide()` in
`experiment.py` is the candidate golden reference: pure integer arithmetic with
Q.4 positions.

## Results

- `results/defeatroaches_sweep.jsonl`: 3 policies × seeds 1–10, `game_step = 8`.
- `results/trace_focus_seed3.jsonl`: 91 recorded snapshots and decisions,
  usable as HDL test vectors.

## Quartus UART probe

`quartus-uart-probe/` is a 115200 8-N-1 UART echo for `10M50DAF484C7G`.
It compiled with Quartus Lite 25.1std in 93 LEs and 67 registers, Fmax
229.89 MHz. The UART pins (`PIN_AB5`/`PIN_AB6`, Arduino D0/D1) are
placeholders until the FTDI wiring is confirmed. The board was not programmed.

```bash
cd /mnt/c/<windows-path-with-these-files>
/mnt/c/altera_lite/25.1std/quartus/bin64/quartus_sh.exe --flow compile uart_echo
/mnt/c/altera_lite/25.1std/quartus/bin64/quartus_pgm.exe -m jtag -o "p;output_files/uart_echo.sof"
```
