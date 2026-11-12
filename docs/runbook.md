# Running the FPGA SC2 demo

This runbook records the working setup on **porotome, November 12, 2026**, using
[PR #6](https://github.com/poroburu/eecs3216-fpga-sc2-tactics/pull/6), commit
`7ce3b0e`. The visible demo runs Windows SC2 and Windows Python, launched from WSL.
The FPGA selects targets over COM5 and drives the physical VGA monitor.

A Linux desktop can run the game and FPGA link headlessly, with terminal output
and the board's VGA display. The normal SC2 game window requires a different
client: Blizzard distributes the native Linux package as a
[headless client](https://github.com/Blizzard/s2client-proto#linux-packages).
This repository's `--window` option specifically launches Windows SC2 from WSL.

## Start the visible demo on this machine

If the board has stayed powered since programming, run this from **WSL**:

```bash
powershell.exe -NoProfile -Command '
  $env:SC2PATH="C:\Users\porob\Games\StarCraft II"
  Set-Location "C:\Users\porob\AppData\Local\Temp\sc2fpga\demo-host"
  & "C:\Users\porob\AppData\Local\Temp\sc2fpga\host-venv\Scripts\python.exe" -u sc2_demo.py --port COM5 --realtime
'
```

This runs one round. Add `--episodes 5` to the Python arguments for five rounds.
The terminal prints each decision and an `EPISODE` summary at the end of a round.
`Result.Defeat` is a game outcome; check `link_errors` to assess the UART link.

Use **Ctrl-C in the launching terminal** to stop early. Closing only a separate
log-viewer window does not stop the game. Closing SC2 itself can end the host with
a connection-error traceback; relaunch using the command above when desired.

The Python environment and host copy above live in Windows Temp. If they have been
cleaned up, rebuild them using [Restore the host environments](#restore-the-host-environments).

## Connect and program the board

Use the DE10-Lite with its USB-Blaster, an external **3.3 V** USB-UART adapter,
and a VGA monitor connected directly to the board:

| Adapter signal | Board connection |
| --- | --- |
| TXD | `GPIO[0]`, header pin 1, FPGA RX |
| RXD | `GPIO[1]`, header pin 2, FPGA TX |
| GND | GND |

The UART is 115200 baud, 8-N-1. On this machine the adapter is **COM5**;
COM3 and COM4 are Bluetooth serial ports. Only one process may use COM5 at a time:
stop the demo before running a hardware check or another game.

Run the following from the PR #6 repository checkout in WSL. The scripts use
Windows Quartus at `C:\altera_lite\25.1std\quartus\bin64` by default.

```bash
# Identify the board and list Windows serial ports.
(cd /mnt/c && /mnt/c/altera_lite/25.1std/quartus/bin64/jtagconfig.exe)
powershell.exe -NoProfile -Command '[System.IO.Ports.SerialPort]::GetPortNames()'

# Build only when the bitstream is missing or the RTL/constraints changed.
tools/demo.sh build

# Reprogram after every board power-cycle; the .sof is volatile.
tools/demo.sh program

# Check all 1,216 frames against the independent reference.
host/.venv/bin/python host/hw_check.py --port win:COM5
```

JTAG should report `USB-Blaster [USB-0]` and a `10M50DA` device. Programming should
report `Successfully performed operation(s)`. The hardware check should finish
with `RESULT PASS 1216/1216`. Keep SW0 fixed during that check; either policy is
supported. Rapid VGA changes during the test are expected.

`tools/demo.sh preflight` and `tools/demo.sh watch` assume SC2 is installed under
`C:\Program Files (x86)\StarCraft II`. That is **not this machine's installation**.
Use the explicit launch command above. `watch` also assumes the WSL host can reach
the Windows SC2 API on `127.0.0.1`; the tested Windows-Python launch keeps the API
connection entirely within Windows and does not depend on that WSL networking setup.

## Show the two policies

1. Set SW0 down for **CLOSEST**, set SW4 through SW1 down, and press KEY0 before
   starting a round.
2. Launch the visible demo. Confirm that the terminal prints `CLOSEST` and target
   indices. The FPGA's cyan VGA banner denotes CLOSEST.
3. Flip SW0 up during play for **FOCUS**. The terminal should print `FOCUS`; the
   VGA banner becomes orange and HEX3 changes from `C` to `F`.
4. Use SW4 through SW1 to select a Marine; HEX0 shows its target. VGA lines show
   the FPGA's target assignments.
5. At the end of a round, confirm `link_errors: 0` and `truncated_steps: 0` in the
   printed JSON summary.

The session log captured both policy names during play, including a CLOSEST to
FOCUS change within one round. The physical VGA was connected, but this runbook
does not certify the appearance of its target lines from a captured monitor image.
See [how it works](how-it-works.md) for the exact targeting rules and display.

## Run the Linux client from WSL

The installed Linux client is SC2 4.10, `Base75689`, under `~/StarCraftII`.
From the repository checkout, use the Linux Python environment and the PowerShell
COM bridge:

```bash
# Real-time game, terminal output, and FPGA VGA; no SC2 game window.
host/.venv/bin/python -u host/sc2_demo.py --port win:COM5 --realtime

# One seeded round in step mode, with a summary instead of every decision.
tools/demo.sh compare 1
```

The bridge opens COM5 on Windows, so WSL does not need the adapter attached using
USB passthrough. `--realtime` sets the pace; it does not enable graphics.

For a matched step-mode sample, keep SW0 in one position and run
`tools/demo.sh compare 5`. Repeat with the other switch position. Real-time runs,
especially rounds where SW0 changes, are not matched benchmark results.

## Run on a native Linux desktop

With the Linux SC2 package, Python dependencies, and the USB-UART adapter available
to Linux, run these commands from the checkout:

```bash
# Discover the adapter; prefer a stable /dev/serial/by-id path when available.
host/.venv/bin/python -m serial.tools.list_ports
ls -l /dev/serial/by-id/

# Replace /dev/ttyUSB0 with the adapter actually discovered above.
host/.venv/bin/python host/hw_check.py --port /dev/ttyUSB0
host/.venv/bin/python -u host/sc2_demo.py --port /dev/ttyUSB0 --realtime

# Five seeded step-mode rounds instead of real-time play.
PORT=/dev/ttyUSB0 tools/demo.sh compare 5
```

The user running Python needs access to the serial device. If access is denied,
check the device's group and the distribution's serial-device access rules.
The native serial path is implemented by pyserial; it was not exercised on a
separate Linux desktop in this session. The Linux game engine was exercised in WSL.

Do **not** add `--window` on native Linux: it uses PowerShell and the Windows
launcher. Blizzard also documents
[EGL and OSMesa rendering options](https://github.com/Blizzard/s2client-proto/blob/master/docs/linux.md)
for image observations through the API; the current demo does not present those
as a desktop game window.

The existing `build`, `program`, and `preflight` wrappers use Windows executables.
For a Linux-only machine, install Linux Quartus and configure USB-Blaster access
before using its tools directly. With the matching `.sof` already available,
the equivalent programming command is:

```bash
jtagconfig
quartus_pgm -c "USB-Blaster [USB-0]" -m jtag \
  -o "p;quartus/sc2fpga/build/sc2fpga.sof"
```

Use the cable name reported by `jtagconfig`. This native Linux programming command
was not run during the Windows/WSL session. Once programmed, the board can stay
powered while a Linux host controls it through UART.

## Restore the host environments

These setup steps are needed only when the existing environments or installations
are missing. Keep source files in the repository and copy the host to Windows for
execution; running Windows Python against the WSL UNC path stalled during this session.

### Linux Python and client

Use Python 3.12, which worked with `burnysc2==7.3.0` in this session:

```bash
uv venv --python 3.12 host/.venv
uv pip install --python host/.venv/bin/python -r host/requirements.txt
```

If `uv` is absent, install it using the
[upstream instructions](https://docs.astral.sh/uv/getting-started/installation/).
The machine's system Python 3.14 lacked pip and ensurepip; creating the environment
with uv avoided changing system Python or installing packages with sudo.

For a missing game installation, download SC2 4.10 from
[Blizzard's Linux packages](https://github.com/Blizzard/s2client-proto#downloads)
and the [DeepMind mini-game maps](https://github.com/google-deepmind/pysc2/releases/tag/v1.2).
The client archive is about 3.8 GiB compressed. Blizzard's archive password
indicates agreement to its linked AI and Machine Learning License; read it before
extracting. From the repository checkout, with `curl`, `gh`, and `unzip` available:

```bash
mkdir -p downloads
curl -fL --retry 2 https://blzdistsc2-a.akamaihd.net/Linux/SC2.4.10.zip \
  -o downloads/SC2.4.10.zip
unzip -q -o -P iagreetotheeula downloads/SC2.4.10.zip -d "$HOME"
chmod +x "$HOME/StarCraftII/Versions/Base75689/SC2_x64"

gh release download v1.2 --repo google-deepmind/pysc2 \
  --pattern mini_games.zip --dir downloads
unzip -q -o downloads/mini_games.zip -d "$HOME/StarCraftII/Maps"

# The Linux engine requested lowercase maps; the archive provided Maps.
test -e "$HOME/StarCraftII/maps" || ln -s Maps "$HOME/StarCraftII/maps"
```

### Windows Python and host copy

The Windows uv executable installed during this session is
`C:\Users\porob\AppData\Local\Temp\sc2fpga\uv\uv.exe`. If it has been removed,
reinstall uv for Windows using the upstream instructions above, and adjust its
path in the following commands.

From the repository checkout in WSL, copy the current host without its Linux venv:

```bash
mkdir -p /mnt/c/Users/porob/AppData/Local/Temp/sc2fpga/demo-host
rsync -a --exclude .venv --exclude __pycache__ --exclude logs \
  host/ /mnt/c/Users/porob/AppData/Local/Temp/sc2fpga/demo-host/

powershell.exe -NoProfile -Command '
  $uv="C:\Users\porob\AppData\Local\Temp\sc2fpga\uv\uv.exe"
  & $uv venv --python 3.12 "C:\Users\porob\AppData\Local\Temp\sc2fpga\host-venv"
  & $uv pip install --python "C:\Users\porob\AppData\Local\Temp\sc2fpga\host-venv\Scripts\python.exe" -r "C:\Users\porob\AppData\Local\Temp\sc2fpga\demo-host\requirements.txt"
'
```

Windows SC2 is version `5.0.17.98310`, installed at
`C:\Users\porob\Games\StarCraft II`. Install or repair the game through Battle.net
if that directory is missing. Place `DefeatRoaches.SC2Map` in its `Maps` directory:

```bash
mkdir -p '/mnt/c/Users/porob/Games/StarCraft II/Maps'
cp "$HOME/StarCraftII/Maps/mini_games/DefeatRoaches.SC2Map" \
  '/mnt/c/Users/porob/Games/StarCraft II/Maps/'
```

In Windows Python, use `--port COM5` and set `SC2PATH` as shown in the launch
command. Omit `--window`: Windows Python launches the visible client natively.

## Logs and recovery

The quick-start command prints to the launching terminal. Its JSON snapshots and
episode summaries append to `host/logs/sc2_demo.jsonl` relative to `demo-host`.
The WSL/Linux launch uses the same relative log path under the repository.

The original session's visible demo was redirected to
`C:\Users\porob\AppData\Local\Temp\sc2fpga\demo-host\windows-demo.log`, and its
JSON trace is in `demo-host\logs\sc2_demo_windows.jsonl`. These are local artifacts,
not committed files. To watch the original terminal log from WSL:

```bash
tail -f /mnt/c/Users/porob/AppData/Local/Temp/sc2fpga/demo-host/windows-demo.log
```

| Symptom | Action |
| --- | --- |
| Board was power-cycled or HEX is dark | Run `tools/demo.sh program` from WSL, then the hardware check. |
| COM5 unavailable or access denied | Stop the existing host, test, or serial monitor before opening the port again. Confirm the adapter's current port. |
| UART timeout or mismatched reply | Check 3.3 V setting, common ground and crossed TX/RX, then program and check again. |
| Linux reports `InvalidMapPath` containing `/maps/` | Ensure the lowercase `maps` link points to `Maps` and that the named map exists. |
| `preflight` says Windows SC2 is missing | It checks the default Program Files path. This machine uses the custom Games path above. |
| Windows Python stalls before the game opens | Use the local Windows host copy instead of executing the script over `\\wsl.localhost\...`. |
| `Cannot write to closing transport` or `Connection already closed` | The SC2 API connection ended. If stopping was intentional, no restart is needed. Otherwise, inspect the log and relaunch; these messages alone do not identify why SC2 disconnected. |
| No adapter or board available | `tools/demo.sh model 1` uses the software reference. Label it as software-only; it does not validate or drive the FPGA. |

## Results from November 12

- Quartus build: 15,847 logic elements, 4,194 registers, 68 embedded 9-bit
  multiplier elements; worst setup slack **+4.283 ns** at 50 MHz.
- FOCUS hardware check: **1,216/1,216 pass**, median UART round trip **16.1 ms**,
  p95 **30.6 ms**, maximum compute **258 cycles / 5.16 microseconds**.
- Linux client in WSL, seed 1, step mode: score 37, 640 game loops, 81 decisions,
  58 orders, **0 link errors**, **0 truncated steps**.
- Visible Windows client: six completed real-time rounds, all with **0 link
  errors** and **0 truncated steps**. Both policies were observed during play.
  The episode summary records the final policy, so it does not establish that
  an entire round used only that policy.
- A later round ended with an SC2 connection-error traceback. Its cause was not
  established. The user ended the session; the demo was not restarted, and the
  separate live-log window was closed.

These real-time rounds are operational checks, not a policy-performance comparison.
See [the presentation script](demo.md) and [earlier results](results.md) for context.
