#!/bin/bash
# F4 驗收: 用標註後 RTL 重建 ai_tile_smoke_tb / attn_smoke_tb 並產新 coverage.dat
set -e
COV_DIR="build/coverage"
COMMON_FLAGS="--coverage --cc --exe --build --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT -Irtl/common"
AI_SRCS="rtl/common/orca_pkg.sv rtl/ai/orca_v63_ai_tile.sv rtl/ai/ctrl/*.sv \
  rtl/ai/cluster/*.sv rtl/ai/pe/*.sv rtl/ai/attention/*.sv rtl/ai/memory/*.sv \
  rtl/ai/noc/*.sv rtl/noc/orca_flit_adapter.sv"
mkdir -p ${COV_DIR}
build_run() {
    local NAME=$1 TOP=$2 TB=$3 SRCS=$4
    echo "== [COV] build ${NAME} (${TOP}) =="
    mkdir -p ${COV_DIR}/${NAME}
    verilator ${COMMON_FLAGS} --Mdir ${COV_DIR}/${NAME}/obj --top-module ${TOP} \
        ${SRCS} ${TB} $(pwd)/tb/cov_main.cpp \
        -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}"
    echo "== [COV] run ${NAME} =="
    (cd ${COV_DIR}/${NAME} && ./obj/V${TOP})
}
build_run ai_smoke   ai_tile_smoke_tb tb/ai_tile_tb/ai_tile_smoke_tb.sv "${AI_SRCS}"
build_run attn_smoke attn_smoke_tb    tb/ai_tile_tb/attn_smoke_tb.sv    "${AI_SRCS}"
echo "== [COV] smoke done =="
