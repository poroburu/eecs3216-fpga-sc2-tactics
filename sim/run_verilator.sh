#!/usr/bin/env bash
# Run the system testbench with Verilator 5 (--binary --timing).
# usage: sim/run_verilator.sh [directed|sc2_trace|random ...]   (default: all three)
# Needs verilator >= 5.0 on PATH (e.g. micromamba create -c conda-forge verilator gxx_linux-64 make).
set -euo pipefail
root=$(realpath "$(dirname "$0")/..")
cd "$root"
RTL="rtl/sc2fpga_pkg.sv rtl/uart_rx.sv rtl/uart_tx.sv rtl/frame_rx.sv rtl/target_select.sv rtl/frame_tx.sv rtl/hex7seg.sv rtl/vga_timing.sv rtl/vga_render.sv rtl/sc2fpga_top.sv"
mkdir -p sim/build
verilator --binary --timing -j 8 -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --top-module tb_sc2fpga -Mdir sim/build/obj $RTL sim/tb_sc2fpga.sv -o tb > sim/build/verilator.log 2>&1 \
  || { tail -40 sim/build/verilator.log; exit 1; }
grep -E "%Warning" sim/build/verilator.log | sed 's/^/  /' | head -20 || true
for s in ${*:-directed sc2_trace random}; do
  ( cd sim/vectors && ../build/obj/tb +VEC=$s.mem ) | tee "sim/build/result_$s.log" | grep -E "RESULT|FAIL|expected:|got:|VGA" | head -40
done
