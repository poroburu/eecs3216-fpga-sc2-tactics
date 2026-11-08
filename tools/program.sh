#!/usr/bin/env bash
# Load a .sof into the DE10-Lite over the USB-Blaster (volatile: lost on power-cycle).
# usage: tools/program.sh [path/to.sof]     (default: quartus/sc2fpga/build/sc2fpga.sof)
set -euo pipefail
root=$(realpath "$(dirname "$0")/..")
sof=$(realpath "${1:-$root/quartus/sc2fpga/build/sc2fpga.sof}")
QUARTUS_BIN=${QUARTUS_BIN:-/mnt/c/altera_lite/25.1std/quartus/bin64}
tmp=/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Local/Temp/sc2fpga
mkdir -p "$tmp"; cp "$sof" "$tmp/program.sof"
cd "$tmp" && "$QUARTUS_BIN/quartus_pgm.exe" -c "USB-Blaster [USB-0]" -m jtag -o "p;program.sof" | grep -E "Error|Successfully performed"
