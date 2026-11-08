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
The usual entry point is `tools/demo.sh` (see [demo.md](../docs/demo.md)).

The host never chooses targets. A missing or invalid reply means no orders for that step,
and the error is counted in the episode summary.
