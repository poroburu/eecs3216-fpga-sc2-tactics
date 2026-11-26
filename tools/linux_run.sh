#!/usr/bin/env bash
# Native Linux one-command build, flash, check, and live SC2 runner for DE10-Lite.
#
# Usage:
#   ./tools/linux_run.sh              # auto-build if RTL changed, flash board, run live two-squad SC2
#   ./tools/linux_run.sh build        # force Quartus compile + print resource & timing summary
#   ./tools/linux_run.sh flash        # program existing .sof onto DE10-Lite
#   ./tools/linux_run.sh check        # flash + run 1,216-vector UART hardware check
#   ./tools/linux_run.sh sim          # run Verilator Lanchester + 1,216-vector regression
#   ./tools/linux_run.sh run [args]   # flash + run sc2_demo.py (passes any extra args through)
#
# Optional env overrides:
#   PORT=/dev/ttyUSB0  SEED=1  EPISODES=1  TIMEOUT=30
set -euo pipefail

ROOT=$(realpath "$(dirname "$0")/..")
cd "$ROOT"

PY="${PY:-$ROOT/.venv/bin/python}"
[[ -x "$PY" ]] || PY=$(command -v python3)

SOF="$ROOT/quartus/sc2fpga/build/sc2fpga.sof"
QWORK="/tmp/sc2fpga-build/sc2fpga"
SEED="${SEED:-1}"
EPISODES="${EPISODES:-1}"
TIMEOUT="${TIMEOUT:-30}"

find_port() {
  if [[ -n "${PORT:-}" ]]; then
    echo "$PORT"
    return
  fi
  local dev
  dev=$(ls /dev/ttyUSB* 2>/dev/null | head -n 1 || true)
  if [[ -z "$dev" ]]; then
    echo "ERROR: No /dev/ttyUSB* UART adapter found. Plug in the FT232R adapter." >&2
    exit 1
  fi
  if [[ ! -r "$dev" || ! -w "$dev" ]]; then
    echo "ERROR: No permission on $dev. Run: sudo usermod -aG uucp \$USER (then re-login)." >&2
    exit 1
  fi
  echo "$dev"
}

check_jtag() {
  if ! jtagconfig 2>/dev/null | grep -q "10M50"; then
    echo "ERROR: DE10-Lite (10M50) not detected on JTAG. Check the USB-B cable." >&2
    jtagconfig || true
    exit 1
  fi
}

needs_build() {
  [[ ! -f "$SOF" ]] && return 0
  [[ -n "$(find rtl quartus/sc2fpga/sc2fpga.qsf quartus/sc2fpga/sc2fpga.sdc -newer "$SOF" 2>/dev/null)" ]]
}

do_build() {
  echo "==> Compiling sc2fpga with Quartus (staging in $QWORK)..."
  rm -rf "$QWORK"
  mkdir -p "$QWORK" "$ROOT/quartus/sc2fpga/build"
  cp quartus/sc2fpga/sc2fpga.{qpf,qsf,sdc} "$QWORK/"
  cp -r rtl "$QWORK/rtl"
  printf '\n' >> "$QWORK/sc2fpga.qsf"
  cat quartus/common/de10_lite_pins.tcl >> "$QWORK/sc2fpga.qsf"

  (cd "$QWORK" && quartus_sh --flow compile sc2fpga) > "$QWORK/build.log" 2>&1 || {
    echo "ERROR: Quartus compile failed:" >&2
    grep -E "^Error|Error \(" "$QWORK/build.log" | head -30 >&2
    exit 1
  }

  local built_sof=""
  if [[ -f "$QWORK/output_files/sc2fpga.sof" ]]; then
    built_sof="$QWORK/output_files/sc2fpga.sof"
  elif [[ -f "$QWORK/sc2fpga.sof" ]]; then
    built_sof="$QWORK/sc2fpga.sof"
  else
    echo "ERROR: Build finished but sc2fpga.sof was not found in $QWORK" >&2
    exit 1
  fi

  cp "$built_sof" "$SOF"
  for f in fit.summary sta.summary; do
    cp "$QWORK/output_files/sc2fpga.$f" "$ROOT/quartus/sc2fpga/build/" 2>/dev/null || \
    cp "$QWORK/sc2fpga.$f" "$ROOT/quartus/sc2fpga/build/" 2>/dev/null || true
  done

  echo "==> Build OK: $SOF"
  grep -E "Total (logic elements|registers|memory bits|pins)|Embedded Multiplier" \
    "$ROOT/quartus/sc2fpga/build/sc2fpga.fit.summary" 2>/dev/null || true
  grep -E "Worst-case setup slack|Worst-case hold slack|Timing requirements not met" \
    "$QWORK/build.log" | head -8 || true
}

do_flash() {
  if [[ ! -f "$SOF" ]]; then
    do_build
  fi
  check_jtag
  echo "==> Flashing DE10-Lite..."
  quartus_pgm -c "USB-Blaster" -m jtag -o "p;$SOF" | grep -E "Using programming|Configuration succeeded|Successfully performed|Error"
}

do_sim() {
  echo "==> Running Verilator Lanchester unit test..."
  verilator --binary --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --top-module tb_lanchester rtl/sc2fpga_pkg.sv rtl/lanchester_ctrl.sv sim/tb_lanchester.sv \
    -Mdir /tmp/obj_lanchester > /tmp/obj_lanchester.log 2>&1 || { tail -30 /tmp/obj_lanchester.log; exit 1; }
  /tmp/obj_lanchester/Vtb_lanchester | grep -E "PASS|FAIL"
  echo "==> Running full 1,216-vector RTL regression..."
  ./sim/run_verilator.sh
}

do_check() {
  local dev
  dev=$(find_port)
  do_flash
  echo "==> Running 1,216-vector hardware check on $dev..."
  "$PY" host/hw_check.py --port "$dev"
}

do_run() {
  local dev
  dev=$(find_port)
  if needs_build; then
    do_build
  fi
  do_flash
  echo "==> Launching live two-squad SC2 on $dev"
  echo "    Switches: SW0 FOCUS/CLOSEST | SW1 Lanchester | SW2 KEY unit (Marine/Roach) | SW3 cautious | SW4 reckless | SW8 pause
    Keys:     KEY0 add unit | KEY1 remove unit | hold both ~1 s = reset"
  "$PY" host/sc2_demo.py \
    --port "$dev" \
    --two-squads \
    --split-demo \
    --episodes "$EPISODES" \
    --seed "$SEED" \
    --realtime \
    --timeout "$TIMEOUT" \
    "$@"
}

cmd="${1:-run}"
shift || true

case "$cmd" in
  run)   do_run "$@" ;;
  build) do_build ;;
  flash) do_flash ;;
  check) do_check ;;
  sim)   do_sim ;;
  *)     sed -n '2,14p' "$0" ;;
esac
