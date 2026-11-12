# Simulation

`tb_sc2fpga.sv` drives the **top level through its UART pin**, the way the PC does. For
each vector it sets `SW0`, transmits the request serially, captures the reply from
`GPIO[1]`, and compares every byte with the reply computed by the independent Python
reference.

```bash
python3 host/gen_vectors.py        # regenerate sim/vectors/*.mem and host/vectors/*.jsonl
sim/run_verilator.sh               # all sets: directed (34), sc2_trace (182), random (1000)
```

Verilator 5 is required. One user-space install that works:

```bash
curl -sL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
./bin/micromamba create -y -p ~/.local/sc2fpga-sim -c conda-forge verilator gxx_linux-64 make
export PATH=~/.local/sc2fpga-sim/bin:$PATH
```

`run_sim.sh` runs the same testbench in Questa FSE on Windows. All three sets pass there too.
It needs the Questa Starter licence listed in the Windows user variable `SALT_LICENSE_SERVER`
(see [results](../docs/results.md)).

`tb_vga_frame.sv` captures one 640×480 frame from `VGA_R/G/B` into a PPM, and
`ppm2png.py` converts it to PNG. That is how `docs/img/vga_sim_p*.png` were made.

The vector format is one 12-bit hex word per line: `4pp` sets `SW0`, `1bb` is a request
byte, `2bb` is an expected reply byte, `300` runs the case, and `fff` ends the file.

## Earlier UART diagnostic (separate build and wire contract)

Use the [diagnostic contract](../docs/diagnostic-protocol.md), not the demo
frames above. The following retained instructions describe that diagnostic only.

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
vlog -sv rtl/diagnostic/uart_rx.sv rtl/diagnostic/uart_tx.sv sim/tb_uart.sv
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
