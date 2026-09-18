#!/bin/bash
# Build & run all cov_f4 coverage TBs (verilator --coverage --cc --exe + cov_main)
# F4: rtl/ai 全 13 模組 100% line coverage
set -e
COV_DIR="build/cov_f4"
COMMON_FLAGS="--coverage --cc --exe --build --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT -Irtl/common"
PKG="rtl/common/orca_pkg.sv"

mkdir -p ${COV_DIR}

build_run() { # $1=name $2=top $3=tb file $4=extra rtl srcs
    local NAME=$1 TOP=$2 TB=$3 SRCS=$4
    echo "== [COV-F4] build ${NAME} (${TOP}) =="
    mkdir -p ${COV_DIR}/${NAME}/obj
    verilator ${COMMON_FLAGS} --Mdir ${COV_DIR}/${NAME}/obj --top-module ${TOP} \
        ${PKG} ${SRCS} ${TB} $(pwd)/tb/cov_main.cpp \
        -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}"
    echo "== [COV-F4] run ${NAME} =="
    (cd ${COV_DIR}/${NAME} && ./obj/V${TOP})
}

AI_ALL="rtl/ai/orca_v63_ai_tile.sv rtl/ai/ctrl/*.sv rtl/ai/cluster/*.sv rtl/ai/pe/*.sv rtl/ai/attention/*.sv rtl/ai/memory/*.sv rtl/ai/noc/*.sv rtl/noc/orca_flit_adapter.sv"

if [ "$1" == "all" ] || [ -z "$1" ]; then
  build_run f4_l2_sram    f4_l2_sram_tb    tb/cov_f4/f4_l2_sram_tb.sv    "rtl/ai/memory/npu_l2_sram.sv"
  build_run f4_hbm3_phy   f4_hbm3_phy_tb   tb/cov_f4/f4_hbm3_phy_tb.sv   "rtl/ai/memory/npu_hbm3_phy.sv"
  build_run f4_cluster    f4_cluster_tb    tb/cov_f4/f4_cluster_tb.sv    "rtl/ai/cluster/npu_cluster.sv rtl/ai/cluster/npu_cu.sv rtl/ai/pe/npu_pe.sv rtl/ai/pe/npu_systolic.sv"
  build_run f4_cu         f4_cu_tb         tb/cov_f4/f4_cu_tb.sv         "rtl/ai/cluster/npu_cu.sv rtl/ai/pe/npu_pe.sv rtl/ai/pe/npu_systolic.sv"
  build_run f4_aix_intf   f4_aix_intf_tb   tb/cov_f4/f4_aix_intf_tb.sv   "rtl/ai/ctrl/npu_aix_intf.sv"
  build_run f4_gscu       f4_gscu_tb       tb/cov_f4/f4_gscu_tb.sv       "rtl/ai/ctrl/npu_gscu.sv"
  build_run f4_tile_noc   f4_tile_noc_tb   tb/cov_f4/f4_tile_noc_tb.sv   "rtl/ai/noc/npu_tile_noc.sv"
  build_run f4_dma        f4_dma_tb        tb/cov_f4/f4_dma_tb.sv        "rtl/ai/ctrl/npu_dma.sv"
  build_run f4_pe         f4_pe_tb         tb/cov_f4/f4_pe_tb.sv         "rtl/ai/pe/npu_pe.sv"
  build_run f4_systolic   f4_systolic_tb   tb/cov_f4/f4_systolic_tb.sv   "rtl/ai/pe/npu_systolic.sv rtl/ai/pe/npu_pe.sv"
  build_run f4_attn       f4_attn_engine_tb tb/cov_f4/f4_attn_engine_tb.sv "rtl/ai/attention/npu_attn_engine.sv"
  build_run f4_hbm3_ctrl  f4_hbm3_ctrl_tb  tb/cov_f4/f4_hbm3_ctrl_tb.sv  "rtl/ai/memory/npu_hbm3_ctrl.sv"
  build_run f4_ai_tile    f4_ai_tile_tb    tb/cov_f4/f4_ai_tile_tb.sv    "${AI_ALL}"
fi

echo "== [COV-F4] done =="
