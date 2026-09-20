#!/bin/bash
# 多 seed 覆蓋合併: 對指定 TB 跑 N 個 seed, verilator_coverage 累積合併
# 用法: bash scripts/run_multiseed.sh <tb_name> <nseeds>   (tb_name=build/coverage 下的目錄名)
set -e
cd "$(dirname "$0")/.."
TB=${1:-cpu_crt}; N=${2:-8}
BIN=$(ls build/coverage/$TB/obj/V* 2>/dev/null | head -1)
[ -z "$BIN" ] && { echo "no binary in build/coverage/$TB — 先跑 rebuild_all_coverage.sh"; exit 1; }
echo "=== $TB: $N seeds 合併 ==="
cd build/coverage/$TB
rm -f coverage.dat
for s in $(seq 1 $N); do
  ./obj/$(basename $BIN) +seed=$((s*2654435761 % 4294967296)) > /dev/null 2>&1 || true
  [ -f coverage.dat ] && echo "  seed $s done ($(stat -c%s coverage.dat)B)"
done
verilator_coverage -write coverage.dat coverage.dat
echo "merged coverage.dat: $(stat -c%s coverage.dat) bytes"
