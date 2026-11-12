#!/usr/bin/env bash
# Compile a Quartus project from WSL using the Windows Quartus install.
# Quartus cannot reliably use \\wsl$ paths, so the project is copied to a Windows temp dir,
# the shared DE10-Lite pin file is appended to the .qsf, and outputs are copied back to build/.
# usage: tools/qbuild.sh <project-dir> <project-name>    (env: QUARTUS_BIN, QWORK)
set -euo pipefail
src=$(realpath "$1"); name=$2; root=$(realpath "$(dirname "$0")/..")
QUARTUS_BIN=${QUARTUS_BIN:-/mnt/c/altera_lite/25.1std/quartus/bin64}
QWORK=${QWORK:-/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Local/Temp/sc2fpga}/$name
mkdir -p "$QWORK" "$src/build"
rsync -a --delete --exclude build --exclude db --exclude incremental_db --exclude output_files "$src/" "$QWORK/"
[ -d "$root/rtl" ] && rsync -a "$root/rtl/" "$QWORK/rtl/"
cat "$root/quartus/common/de10_lite_pins.tcl" >> "$QWORK/$name.qsf"
cd "$QWORK"
"$QUARTUS_BIN/quartus_sh.exe" --flow compile "$name" > build.log 2>&1 || { grep -E "^Error|Error \(" build.log | head -30; exit 1; }
cp output_files/$name.sof "$src/build/" 2>/dev/null || cp $name.sof "$src/build/"
for f in fit.summary sta.summary flow.rpt; do cp output_files/$name.$f "$src/build/" 2>/dev/null || cp $name.$f "$src/build/" 2>/dev/null || true; done
grep -E "Total (logic elements|registers|memory bits|pins)|Embedded Multiplier|Total PLLs" "$src/build/$name.fit.summary" || true
grep -E "Critical Warning" build.log | head -5 || true
echo "SOF: $src/build/$name.sof"
