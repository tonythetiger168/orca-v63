#!/bin/bash
# ORCA v6.3.3 cov-f2: execution-unit directed coverage TB runner
# 用法: bash tb/cov_f2/run_cov_f2.sh [tb_name ...]   (無參數 = 全部)
set -e
cd "$(dirname "$0")/../.."

COV_DIR=build/cov_f2
COMMON_FLAGS="--coverage --cc --exe --build --timing -j 1 -Wno-fatal -Wno-BLKLOOPINIT -Irtl/common"
PKG=rtl/common/orca_pkg.sv
EXU=rtl/cpu/execution

mkdir -p ${COV_DIR}

build_run() { # $1=name $2=top $3=tb $4=srcs
    local NAME=$1 TOP=$2 TB=$3 SRCS=$4
    echo "== [COV-F2] build ${NAME} (${TOP}) =="
    mkdir -p ${COV_DIR}/${NAME}
    verilator ${COMMON_FLAGS} --Mdir ${COV_DIR}/${NAME}/obj --top-module ${TOP} \
        ${SRCS} ${TB} $(pwd)/tb/cov_main.cpp \
        -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}"
    echo "== [COV-F2] run ${NAME} =="
    (cd ${COV_DIR}/${NAME} && ./obj/V${TOP})
}

run_one() {
  case "$1" in
    alu)        build_run alu        exu_alu_cov_tb        tb/cov_f2/exu_alu_cov_tb.sv        "${PKG} ${EXU}/exu_alu.sv" ;;
    mul)        build_run mul        exu_mul_cov_tb        tb/cov_f2/exu_mul_cov_tb.sv        "${PKG} ${EXU}/exu_mul.sv" ;;
    vec)        build_run vec        exu_vec_cov_tb        tb/cov_f2/exu_vec_cov_tb.sv        "${PKG} ${EXU}/exu_vec.sv" ;;
    fpu)        build_run fpu        exu_fpu_cov_tb        tb/cov_f2/exu_fpu_cov_tb.sv        "${PKG} ${EXU}/exu_fpu.sv" ;;
    bru_crypto) build_run bru_crypto exu_bru_crypto_cov_tb tb/cov_f2/exu_bru_crypto_cov_tb.sv "${PKG} ${EXU}/exu_bru.sv ${EXU}/exu_crypto.sv" ;;
    prf)        build_run prf        prf_cov_tb            tb/cov_f2/prf_cov_tb.sv            "${PKG} ${EXU}/prf.sv" ;;
    *) echo "unknown TB: $1"; exit 1 ;;
  esac
}

if [ $# -eq 0 ]; then
  for t in alu mul vec fpu bru_crypto prf; do run_one $t; done
else
  for t in "$@"; do run_one $t; done
fi
