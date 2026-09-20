#!/bin/bash
# F4 域全部 14 個 TB 重建 (環境重置後) - 全程 -j 1 序列執行
cd /mnt/agents/output/orca_v63_package || exit 1

AI_SRCS="rtl/common/orca_pkg.sv rtl/ai/orca_v63_ai_tile.sv rtl/ai/*/*.sv rtl/noc/orca_flit_adapter.sv rtl/noc/orca_noc_router.sv rtl/noc/orca_noc_link.sv"

run_one () {
  local name="$1"; local srcs="$2"
  echo "===== BUILD $name ====="
  mkdir -p build/cov_final/$name/obj && rm -rf build/cov_final/$name/obj/*
  verilator --coverage --cc --exe --build --timing -j 1 -Wno-fatal -Wno-BLKLOOPINIT \
    -Irtl/common --Mdir build/cov_final/$name/obj --top-module $name \
    $srcs tb/cov_f4/$name.sv $(pwd)/tb/cov_main.cpp \
    -CFLAGS "-DVM_TOP_HDR=V${name}.h -DVM_TOP=V${name}" \
    > build/cov_final/$name/build.log 2>&1
  if [ $? -ne 0 ]; then echo "BUILD FAIL $name"; return 1; fi
  ( cd build/cov_final/$name && rm -f fsm.log && ./obj/V${name} > run.log 2>&1 )
  grep -q "TB PASS" build/cov_final/$name/run.log && echo "PASS $name" || echo "RUN FAIL $name"
}

run_one f4_pe_tb          "rtl/common/orca_pkg.sv rtl/ai/pe/npu_pe.sv"
run_one f4_attn_engine_tb "rtl/common/orca_pkg.sv rtl/ai/attention/npu_attn_engine.sv"
run_one f4_cu_tb          "rtl/common/orca_pkg.sv rtl/ai/cluster/npu_cu.sv rtl/ai/pe/*.sv"
run_one f4_aix_intf_tb    "rtl/common/orca_pkg.sv rtl/ai/ctrl/npu_aix_intf.sv"
run_one f4_dma_tb         "rtl/common/orca_pkg.sv rtl/ai/ctrl/npu_dma.sv"
run_one f4_gscu_tb        "rtl/common/orca_pkg.sv rtl/ai/ctrl/npu_gscu.sv"
run_one f4_hbm3_ctrl_tb   "rtl/common/orca_pkg.sv rtl/ai/memory/npu_hbm3_ctrl.sv"
run_one f4_hbm3_phy_tb    "rtl/common/orca_pkg.sv rtl/ai/memory/npu_hbm3_phy.sv"
run_one f4_l2_sram_tb     "rtl/common/orca_pkg.sv rtl/ai/memory/npu_l2_sram.sv"
run_one f4_tile_noc_tb    "rtl/common/orca_pkg.sv rtl/ai/noc/npu_tile_noc.sv rtl/noc/orca_flit_adapter.sv"
run_one f4_acc_tb         "rtl/common/orca_pkg.sv rtl/ai/pe/npu_acc.sv"
run_one f4_systolic_tb    "rtl/common/orca_pkg.sv rtl/ai/pe/npu_systolic.sv rtl/ai/pe/npu_pe.sv"
run_one f4_cluster_tb     "$AI_SRCS"
run_one f4_ai_tile_tb     "$AI_SRCS"
echo "ALL DONE"
