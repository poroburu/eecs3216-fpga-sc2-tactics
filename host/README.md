# Python host components

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
initial squad at an observed round boundary. This repository does not launch SC2
yet; mocks establish sequencing, not legal SC2 actions or map compatibility.
The independent tactical reference and actual API binding remain required.
