# Verification commands

From the repository root:

```bash
python3 -m unittest discover -s sim -p 'test_*.py' -v
python3 sim/run_rtl.py
```

Verified with Python 3.12.3 and Icarus Verilog 12.0. Put `iverilog`/`vvp` on
PATH, or set `IVERILOG`/`VVP` (compiler flags allowed). The runner creates a
temporary directory and enforces a 60-second timeout per testbench.

The testbenches use ordinary SystemVerilog tasks and `$fatal`. For ModelSim:

```tcl
vlib work
vlog -sv rtl/uart_rx.sv rtl/uart_tx.sv sim/tb_uart.sv
vsim -c tb_uart -do "run -all; quit -f"
```

The packet bench also needs the runner's temporary manifest/mem files. Icarus
is the exercised path; the installed ModelSim license was invalid in the earlier
bring-up session, so ModelSim has not been validated.

`fixtures/protocol.json` contains 21 committed byte fixtures: empty/maximal squads,
START/reset, replies, bad checksum/version/type, oversize, truncation and semantic
errors. `make_fixtures.py` authors bytes independently with lists/shifts; it does
not import the production codec. Never regenerate expected bytes during tests.
Review both fixture bytes and spec for a contract revision. Python encoders/
decoders and RTL RX/TX compare against the same fixed bytes.

`run_rtl.py` adds 1,000 seeded random transport snapshots, including corruption.
It checks acceptance/rejection, active payload/metadata preservation, consumer
locking, timeout, reset and framing-error recovery. UART tests cover all byte
values, back-to-back traffic, baud skew, false starts, invalid stops, reset and an
independent TX serial monitor. These are transport tests, **not** the proposal's
1,000 tactical state/history comparisons.

Python tests cover chunking/noise, timeout, numeric bounds, tags, commands,
matching replies, retries, reset, full capacity and fail-closed stepping. See
[verification](../docs/verification.md) for hardware evidence and remaining tests.
