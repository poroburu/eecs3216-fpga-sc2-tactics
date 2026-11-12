#!/usr/bin/env bash
# Run the system testbench in Questa FSE (Windows install) from WSL.
# usage: sim/run_sim.sh [directed|sc2_trace|random ...]     (default: all three)
# Licence: the Windows user variable SALT_LICENSE_SERVER must list a Questa Starter licence
# whose NIC ID matches this PC.
set -euo pipefail
root=$(realpath "$(dirname "$0")/..")
QUESTA=${QUESTA:-/mnt/c/altera_lite/25.1std/questa_fse/win64}
W=${SIMWORK:-/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Local/Temp/sc2fpga/sim}
mkdir -p "$W"
rsync -a "$root/rtl/" "$W/rtl/"; rsync -a "$root/sim/" "$W/sim/"
cd "$W"
RTL="rtl/sc2fpga_pkg.sv rtl/uart_rx.sv rtl/uart_tx.sv rtl/frame_rx.sv rtl/target_select.sv rtl/frame_tx.sv rtl/hex7seg.sv rtl/vga_timing.sv rtl/vga_render.sv rtl/sc2fpga_top.sv"
"$QUESTA/vlib.exe" work > /dev/null 2>&1 || true
"$QUESTA/vlog.exe" -sv -quiet $RTL sim/tb_sc2fpga.sv > vlog.log 2>&1 || { cat vlog.log; exit 1; }
for s in ${*:-directed sc2_trace random}; do
  log="vsim_$s.log"
  if ! "$QUESTA/vsim.exe" -c -quiet tb_sc2fpga +VEC="sim/vectors/$s.mem" \
      -do "onerror {quit -code 1}; run -all; quit -f" > "$log" 2>&1; then
    cat "$log"
    exit 1
  fi
  cp "$log" "$root/sim/"
  grep -E "RESULT|FAIL|expected:|got:|VGA frame|Error|Fatal" "$log" | head -40
  grep -Eq 'RESULT .*: [1-9][0-9]* cases, [1-9][0-9]* pass, 0 fail' "$log"
  if grep -Eq 'FAIL|Error|Fatal' "$log"; then exit 1; fi
done
