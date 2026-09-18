#!/usr/bin/env bash
# final_cov.sh <start_idx> <end_idx> — build+run coverage for TBs in final_list.txt slice
set -u
cd /mnt/agents/output/orca_v63_package
LIST=/mnt/agents/output/final_list.txt
COV=build/cov_final
mkdir -p $COV
S=${1:-1}; E=${2:-41}
CPU_SRCS="rtl/common/orca_pkg.sv rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/ifu_fetch.sv rtl/cpu/frontend/ifu_btb.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"
TILE_SRCS="$CPU_SRCS rtl/cpu/orca_v63_cpu_tile.sv"
AI_SRCS="rtl/common/orca_pkg.sv rtl/ai/orca_v63_ai_tile.sv rtl/ai/*/*.sv rtl/noc/orca_flit_adapter.sv rtl/noc/orca_noc_router.sv rtl/noc/orca_noc_link.sv"
i=0
while IFS='|' read -r NAME TOP SRCS TB; do
  i=$((i+1))
  [ $i -lt $S ] && continue
  [ $i -gt $E ] && break
  [ "$SRCS" = "CPU" ] && SRCS="$CPU_SRCS"
  [ "$SRCS" = "TILE" ] && SRCS="$TILE_SRCS"
  [ "$SRCS" = "AI" ] && SRCS="$AI_SRCS"
  [ "$SRCS" = "SOC" ] && SRCS="rtl/common/orca_pkg.sv tb/cov_soc/stub_tiles.sv rtl/noc/orca_flit_adapter.sv rtl/noc/orca_noc_router.sv rtl/pad/*.sv rtl/noc/orca_bow_link.sv rtl/soc/orca_v63_soc.sv"
  [ -f "$COV/$NAME/coverage.dat" ] && { echo "SKIP $NAME"; continue; }
  mkdir -p "$COV/$NAME/obj"
  rm -rf "$COV/$NAME/obj"/*
  echo "=== [$i] $NAME top=$TOP"
  verilator --coverage --cc --exe --build --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT \
    -Irtl/common --Mdir "$COV/$NAME/obj" --top-module "$TOP" \
    $SRCS "$TB" $(pwd)/tb/cov_main.cpp \
    -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}" \
    > "$COV/$NAME/build.log" 2>&1
  if [ ! -x "$COV/$NAME/obj/V${TOP}" ]; then
    echo "RETRY-j1 $NAME"
    verilator --coverage --cc --exe --build --timing -j 1 -Wno-fatal -Wno-BLKLOOPINIT \
      -Irtl/common --Mdir "$COV/$NAME/obj" --top-module "$TOP" \
      $SRCS "$TB" $(pwd)/tb/cov_main.cpp \
      -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}" \
      >> "$COV/$NAME/build.log" 2>&1
  fi
  if [ ! -x "$COV/$NAME/obj/V${TOP}" ]; then echo "BUILDFAIL $NAME"; tail -5 "$COV/$NAME/build.log"; continue; fi
  ( cd "$COV/$NAME" && ./obj/V${TOP} > run.log 2>&1 )
  if [ -f "$COV/$NAME/coverage.dat" ]; then echo "OK $NAME"; grep -E "PASS|FAIL" "$COV/$NAME/run.log" | head -3
  else echo "RUNFAIL $NAME"; tail -5 "$COV/$NAME/run.log"; fi
done < $LIST
echo "SLICE DONE"
