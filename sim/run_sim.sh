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
  "$QUESTA/vsim.exe" -c -quiet tb_sc2fpga +VEC=sim/vectors/$s.mem -do "run -all; quit -f" > "vsim_$s.log" 2>&1 || true
  grep -E "RESULT|FAIL|expected:|got:|VGA frame|Error|Fatal" "vsim_$s.log" | head -40
  cp "vsim_$s.log" "$root/sim/" 2>/dev/null || true
done
