#!/usr/bin/env bash
# sva_build.sh: 建置並執行 3 個 SVA 覆蓋率 TB (-j 1, 帶 --coverage)
# 工具鏈: pip 版 Verilator 5.30.3 (/tmp/v530/verilator, VERILATOR_ROOT)
#   - GCC 需 -fcoroutines (verilated_timing.cpp 用 C++20 coroutine)
#   - VK_PCH_I_FAST/SLOW 清空: 此套件 verilated.mk 的 GCC PCH 規則會傳
#     不存在的裸檔名給 g++ (linker input not found), 故關閉 PCH 引用
set -u
cd /mnt/agents/output/orca_v63_package
export VERILATOR_ROOT=${VERILATOR_ROOT:-/tmp/v530/verilator}
V=$VERILATOR_ROOT/bin/verilator
VCOV=$VERILATOR_ROOT/include/verilated_cov.cpp
PKG=rtl/common/orca_pkg.sv
CPU_SRCS="$PKG rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/ifu_fetch.sv rtl/cpu/frontend/ifu_btb.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"
COV=build/sva_cov
mkdir -p $COV

build_run() { # $1=name $2=srcs $3=tb
  local N=$1 SRCS=$2 TB=$3
  echo "=== [SVA] build $N ==="
  mkdir -p $COV/$N/obj
  $V --coverage --cc --exe --timing --assert -j 1 -Wno-fatal -Wno-BLKLOOPINIT \
    -Irtl/common --Mdir $COV/$N/obj --top-module $N \
    $SRCS $TB $(pwd)/tb/cov_main.cpp $VCOV \
    -CFLAGS "-DVM_TOP_HDR=V$N.h -DVM_TOP=V$N -fcoroutines" \
    > $COV/$N/build.log 2>&1 \
  && make -C $COV/$N/obj -f V$N.mk -j 1 VK_PCH_I_FAST= VK_PCH_I_SLOW= \
    >> $COV/$N/build.log 2>&1
  if [ ! -x $COV/$N/obj/V$N ]; then
    echo "BUILDFAIL $N"; tail -30 $COV/$N/build.log; return
  fi
  echo "=== [SVA] run $N ==="
  ( cd $COV/$N && ./obj/V$N > run.log 2>&1 )
  grep -E "PASS|FAIL|SVA_COV" $COV/$N/run.log | head -5
}

build_run sva_rob_tb "$PKG rtl/cpu/commit/*.sv rtl/cpu/rename/rnu_freelist.sv tb/sva_cov/sva_rob_cov.sv" tb/sva_cov/sva_rob_tb.sv
build_run sva_cpu_core_tb "$CPU_SRCS tb/sva_cov/sva_cpu_core_cov.sv" tb/sva_cov/sva_cpu_core_tb.sv
build_run sva_noc_tb "$PKG rtl/noc/orca_noc_router.sv rtl/noc/orca_chi_coh.sv tb/sva_cov/sva_noc_cov.sv" tb/sva_cov/sva_noc_tb.sv
echo "=== SVA BUILD DONE ==="
