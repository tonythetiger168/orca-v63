#!/bin/bash
# f3_run.sh: 建置並執行 tb/cov_f3 下的 coverage TB
# 用法: bash scripts/f3_run.sh [name ...]   (無參數 = 全部 5 個)
set -e
COV_DIR="build/cov_f3"
COMMON_FLAGS="--coverage --cc --exe --build --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT -Irtl/common"
PKG="rtl/common/orca_pkg.sv"
CPU_ALL="rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/*.sv rtl/cpu/decode/*.sv \
  rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv \
  rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"

mkdir -p ${COV_DIR}

build_run() { # $1=name $2=tb $3=srcs
    local NAME=$1 TB=$2 SRCS=$3
    echo "== [F3] build ${NAME} =="
    mkdir -p ${COV_DIR}/${NAME}/obj
    verilator ${COMMON_FLAGS} --Mdir ${COV_DIR}/${NAME}/obj --top-module ${NAME}_tb \
        ${SRCS} ${TB} $(pwd)/tb/cov_main.cpp \
        -CFLAGS "-DVM_TOP_HDR=V${NAME}_tb.h -DVM_TOP=V${NAME}_tb"
    echo "== [F3] run ${NAME} =="
    (cd ${COV_DIR}/${NAME} && ./obj/V${NAME}_tb 2>&1 | tee run.log)
}

run_one() {
    case $1 in
      f3_cmt)      build_run f3_cmt      tb/cov_f3/f3_cmt_tb.sv      "${PKG} rtl/cpu/commit/*.sv" ;;
      f3_rnu_isu)  build_run f3_rnu_isu  tb/cov_f3/f3_rnu_isu_tb.sv  "${PKG} rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv" ;;
      f3_lsu_ls)   build_run f3_lsu_ls   tb/cov_f3/f3_lsu_ls_tb.sv   "${PKG} rtl/cpu/memory/lsu_ld.sv rtl/cpu/memory/lsu_st.sv" ;;
      f3_lsu_misc) build_run f3_lsu_misc tb/cov_f3/f3_lsu_misc_tb.sv "${PKG} rtl/cpu/memory/lsu_mshr.sv rtl/cpu/memory/lsu_dtlb.sv rtl/cpu/memory/lsu_dcache.sv rtl/cpu/cache/dcache.sv" ;;
      f3_core_poke) build_run f3_core_poke tb/cov_f3/f3_core_poke_tb.sv "${PKG} ${CPU_ALL}" ;;
      *) echo "unknown TB: $1"; exit 1 ;;
    esac
}

if [ $# -eq 0 ]; then
    set -- f3_cmt f3_rnu_isu f3_lsu_ls f3_lsu_misc f3_core_poke
fi
for n in "$@"; do run_one $n; done
echo "== [F3] done =="
