#!/usr/bin/env bash
# BUG-A regression: rebuild+run f3_core_poke_tb, f3_cmt_tb, cpu_directed_tb, tb_top
set -u
cd /mnt/agents/output/orca_v63_package
COV=build/cov_final
CPU_SRCS="rtl/common/orca_pkg.sv rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/ifu_fetch.sv rtl/cpu/frontend/ifu_btb.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"

build_one() {
  local NAME=$1 TOP=$2 SRCS=$3 TB=$4
  rm -rf "$COV/$NAME/obj" "$COV/$NAME/coverage.dat"
  mkdir -p "$COV/$NAME/obj"
  echo "=== BUILD $NAME"
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
  if [ ! -x "$COV/$NAME/obj/V${TOP}" ]; then echo "BUILDFAIL $NAME"; tail -5 "$COV/$NAME/build.log"; return; fi
  ( cd "$COV/$NAME" && ./obj/V${TOP} > run.log 2>&1 )
  echo "RUN-DONE $NAME"
  grep -E "PASS|FAIL" "$COV/$NAME/run.log" | head -5
}

build_one f3_cmt_tb       f3_cmt_tb       "rtl/common/orca_pkg.sv rtl/cpu/commit/*.sv" tb/cov_f3/f3_cmt_tb.sv
build_one f3_core_poke_tb f3_core_poke_tb "$CPU_SRCS" tb/cov_f3/f3_core_poke_tb.sv
build_one cpu_directed_tb cpu_directed_tb "$CPU_SRCS" tb/cpu_tile_tb/cpu_directed_tb.sv
build_one tb_top          tb_top          "$CPU_SRCS" tb/cpu_tile_tb/tb_top.sv
echo "ALL-REGRESS-DONE"
