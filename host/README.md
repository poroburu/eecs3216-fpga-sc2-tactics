# Host (Python, runs in WSL)

| File | Role |
|---|---|
| `sc2fpga/protocol.py` | Frame encode/decode (mirrors [protocol.md](../docs/protocol.md)) |
| `sc2fpga/reference.py` | Independent reference: target rule, cycle count, error rules |
| `sc2fpga/transport.py` | `win:COM5` (PowerShell bridge), `/dev/ttyUSB0` (pyserial), `model` (reference as fake board) |
| `bridge/com_bridge.ps1` | Lets WSL use the Windows COM port; no `usbipd` needed |
| `sc2fpga/winclient.py` | Starts the visible Windows SC2 client from WSL (works around burnysc2's launcher) |
| `sc2fpga/vectors.py`, `gen_vectors.py` | Test vectors for the testbench and the board |
| `hw_check.py` | Sends the vectors to the board and compares bit-exactly |
| `sc2_demo.py` | The SC2 ↔ FPGA game loop |

Setup: `uv venv host/.venv && VIRTUAL_ENV=host/.venv uv pip install -r host/requirements.txt`.
The usual entry point is `tools/demo.sh` (see [demo runbook](../docs/demo-runbook.md)).

The host never chooses targets. A missing or invalid reply means no orders for that step,
and the error is counted in the episode summary.

## Earlier UART diagnostic (separate build and wire contract)

Use the [diagnostic contract](../docs/diagnostic-protocol.md), not the demo
frames above. The following retained instructions describe that diagnostic only.

Python 3.12; codec/tests use only the standard library. Physical UART uses
pySerial 3.5: `python3 -m pip install -r host/requirements.txt` (use a venv or
Python on the machine owning the serial port).

- `protocol.py`: v1 codec, semantic validation, bounded stream decoder.
- `transport.py`: 115200 8N1, matching IDs, bounded identical retries, explicit
  failures and raw-byte JSONL logs. No software tactical fallback.
- `bridge.py`: round-stable tags, quantization, native-tag intents, confirmed/current
  order deduplication and fail-closed single-step backend sequencing.
- `uart_tool.py`: adapter loopback and synthetic capacity benchmark commands.
- `test_frames.ps1`: physical Windows diagnostic test with committed byte fixtures.

From the repository root, for adapter-only TXD/RXD loopback, FPGA disconnected:

```bash
python3 -m host.uart_tool loopback --port /dev/ttyUSB0 --log loopback.jsonl \
  --driver-version ACTUAL_VERSION --latency-timer-ms ACTUAL_SETTING
```

Use COM5 with Windows Python on the verified setup. Logs require new paths.
Read [bring-up](../docs/uart-bringup.md) before wiring. The same tool supports
`benchmark` (same options, plus `--round-id 1 --repeat 10`) once the tactical
core exists. It sends 0/0, 4/4, 8/8 and 16/16 synthetic snapshots and requires
successful validated decisions. It **fails with UNSUPPORTED on the current
board diagnostic**. Reset the FPGA before a new host process/session.

Logs separate serialization, theoretical 10-bits/byte line time, FPGA cycles
and whole-exchange elapsed time. Host timestamps/driver flush do not independently
measure physical wire transit; use a logic analyzer for that. Retries/errors
are marked and excluded as clean latency samples. Record driver/OS, CPU load,
throughput and timer setting in FTDI comparisons. The current 16 ms Windows
FTDI timer was read without modification.

`single_step` needs a qualified backend implementing `observe`, `current_orders`,
`apply`, `step`. Supply only eligible visible unit facts, with authored damage
and effective reach for the supported matchup. `apply` revalidates live tags and
raises on native action failure before the game advances. Start with the complete
initial squad at an observed round boundary. The Python bridge does not launch
SC2; its mocks establish sequencing, not legal SC2 actions or map compatibility.
The independent tactical reference and actual tactical API binding remain required.

The [C++ API submodule and Linux smoke check](../docs/sc2-linux.md) provide a
bounded launch/observe/single-step test against the installed headless client.
Build that optional target with `cmake -S host/sc2 -B build/sc2` and
`cmake --build build/sc2 --target sc2_smoke -j 4`. It is separate from the Python
UART transport and does not issue a hardware-derived game action.
