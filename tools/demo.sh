#!/usr/bin/env bash
# One entry point for the lab demo. Run from anywhere inside the repo.
#
#   tools/demo.sh preflight     check board (JTAG), adapter (COM5), SC2 installs, Python env
#   tools/demo.sh build         compile the bitstream with Quartus (~45 s)
#   tools/demo.sh program       load the bitstream into the DE10-Lite (volatile)
#   tools/demo.sh check         send 1,216 test vectors over UART, compare bit-exactly
#   tools/demo.sh watch [seed]  visible Windows SC2, real time, FPGA picks every target
#   tools/demo.sh compare [n]   n seeded headless games (step mode) with the current SW0 policy
#   tools/demo.sh model [p]     same as compare but the Python reference replaces the board (p = 0/1)
#   tools/demo.sh sim           run the Verilator testbench (needs verilator on PATH)
set -euo pipefail
root=$(realpath "$(dirname "$0")/..")
cd "$root"
PY=${PY:-host/.venv/bin/python}
PORT=${PORT:-win:COM5}
QB=${QUARTUS_BIN:-/mnt/c/altera_lite/25.1std/quartus/bin64}
cmd=${1:-help}; shift || true

case "$cmd" in
  preflight)
    echo "== JTAG (USB-Blaster + 10M50DA expected)"; (cd /mnt/c && "$QB/jtagconfig.exe") | tr -d '\r'
    echo "== Serial ports on Windows"; powershell.exe -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" | tr -d '\r'
    echo "== Linux SC2 (headless)"; ls -d "$HOME/StarCraftII/Versions/"Base* 2>/dev/null || echo "missing ~/StarCraftII"
    echo "== Windows SC2 (window)"; ls -d "/mnt/c/Program Files (x86)/StarCraft II/Versions/"Base* 2>/dev/null || echo "missing"
    ls "/mnt/c/Program Files (x86)/StarCraft II/Maps/DefeatRoaches.SC2Map" 2>/dev/null || echo "  copy ~/StarCraftII/Maps/DefeatRoaches.SC2Map into the Windows Maps folder"
    echo "== Python"; $PY -c "import sc2, serial; print('burnysc2 + pyserial OK')"
    echo "== Bitstream"; ls -la quartus/sc2fpga/build/sc2fpga.sof 2>/dev/null || echo "not built: tools/demo.sh build" ;;
  build)   tools/qbuild.sh quartus/sc2fpga sc2fpga ;;
  program) tools/program.sh ;;
  check)   python3 host/hw_check.py --port "$PORT" "$@" ;;
  watch)   $PY host/sc2_demo.py --port "$PORT" --window --realtime --seed "${1:-1}" ;;
  compare) $PY host/sc2_demo.py --port "$PORT" --episodes "${1:-5}" --seed 1 --quiet ;;
  model)   $PY host/sc2_demo.py --port model --policy "${1:-1}" --episodes "${2:-5}" --seed 1 --quiet ;;
  sim)     sim/run_verilator.sh ;;
  *)       sed -n '2,13p' "$0" ;;
esac
