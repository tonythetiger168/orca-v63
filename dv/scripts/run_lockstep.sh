#!/bin/bash
# ORCA async-lockstep 驗證: RTL vs 內嵌 ISS (離線, 無需 Spike)
set -e; cd "$(dirname "$0")/.."
CPU_SRCS="rtl/common/orca_pkg.sv rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/*.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv dv/golden/orca_iss.sv dv/lockstep/orca_lockstep_tb.sv"
rm -rf build/dv_lockstep
verilator --binary --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT -Wno-WIDTH -Wno-UNOPTFLAT \
  -Irtl/common --Mdir build/dv_lockstep $CPU_SRCS --top-module orca_lockstep_tb
./build/dv_lockstep/Vorca_lockstep_tb +seed=${1:-42}
