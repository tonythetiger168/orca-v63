#!/usr/bin/env bash
# sva_regress.sh: cmt_rob retire-clear-valid 修復回歸 (lead 核准項 1b/1c)
# 1) f3_cmt_tb 重建 coverage 到 build/cov_final/f3_cmt_tb (含 coverage.dat)
# 2) f3_core_poke_tb / cpu_directed_tb / tb_top 功能回歸 (build/sva_regress/)
set -u
cd /mnt/agents/output/orca_v63_package
PKG=rtl/common/orca_pkg.sv
CPU_SRCS="$PKG rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/ifu_fetch.sv rtl/cpu/frontend/ifu_btb.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"

echo "=== [1] f3_cmt_tb (cov_final, --coverage) ==="
rm -rf build/cov_final/f3_cmt_tb
mkdir -p build/cov_final/f3_cmt_tb/obj
verilator --coverage --cc --exe --build --timing -j 1 -Wno-fatal -Wno-BLKLOOPINIT \
  -Irtl/common --Mdir build/cov_final/f3_cmt_tb/obj --top-module f3_cmt_tb \
  $PKG rtl/cpu/commit/*.sv tb/cov_f3/f3_cmt_tb.sv $(pwd)/tb/cov_main.cpp \
  -CFLAGS "-DVM_TOP_HDR=Vf3_cmt_tb.h -DVM_TOP=Vf3_cmt_tb" \
  > build/cov_final/f3_cmt_tb/build.log 2>&1
if [ -x build/cov_final/f3_cmt_tb/obj/Vf3_cmt_tb ]; then
  ( cd build/cov_final/f3_cmt_tb && ./obj/Vf3_cmt_tb > run.log 2>&1 )
  grep -E "PASS|FAIL|ERR" build/cov_final/f3_cmt_tb/run.log | head -5
else
  echo "BUILDFAIL f3_cmt_tb"; tail -20 build/cov_final/f3_cmt_tb/build.log
fi

mkdir -p build/sva_regress
regress() { # $1=name $2=tb $3=srcs
  local N=$1 TB=$2 SRCS=$3
  echo "=== [reg] $N ==="
  rm -rf build/sva_regress/$N; mkdir -p build/sva_regress/$N/obj
  verilator --coverage --cc --exe --build --timing --assert -j 1 -Wno-fatal -Wno-BLKLOOPINIT \
    -Irtl/common --Mdir build/sva_regress/$N/obj --top-module $N \
    $SRCS $TB $(pwd)/tb/cov_main.cpp \
    -CFLAGS "-DVM_TOP_HDR=V$N.h -DVM_TOP=V$N" \
    > build/sva_regress/$N/build.log 2>&1
  if [ -x build/sva_regress/$N/obj/V$N ]; then
    ( cd build/sva_regress/$N && ./obj/V$N > run.log 2>&1 )
    grep -E "PASS|FAIL" build/sva_regress/$N/run.log | head -3
  else
    echo "BUILDFAIL $N"; tail -10 build/sva_regress/$N/build.log
  fi
}

regress f3_core_poke_tb tb/cov_f3/f3_core_poke_tb.sv "$CPU_SRCS"
regress cpu_directed_tb tb/cpu_tile_tb/cpu_directed_tb.sv "$CPU_SRCS"
regress tb_top         tb/cpu_tile_tb/tb_top.sv         "$CPU_SRCS"
echo "=== REGRESS DONE ==="
