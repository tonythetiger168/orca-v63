#!/bin/bash
# ORCA v6.3 - 全量 coverage TB 重建腳本（環境重置後一鍵恢復）
# 建置所有 coverage TB -> 各產 coverage.dat -> 合併 -> 報告
set -e
cd "$(dirname "$0")/.."
CFLAGS_BASE='-Wno-fatal -Wno-BLKLOOPINIT -Wno-WIDTH -Wno-UNOPTFLAT'
VFLAGS="--coverage --cc --exe --build --timing -j 2 $CFLAGS_BASE -Irtl/common"
MAIN=$(pwd)/tb/cov_main.cpp
CPU_SRCS="rtl/common/orca_pkg.sv rtl/cpu/orca_v63_cpu_core.sv rtl/cpu/frontend/*.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"
AI_SRCS="rtl/common/orca_pkg.sv rtl/ai/orca_v63_ai_tile.sv rtl/ai/ctrl/*.sv rtl/ai/cluster/*.sv rtl/ai/pe/*.sv rtl/ai/attention/*.sv rtl/ai/memory/*.sv rtl/ai/noc/*.sv rtl/noc/orca_flit_adapter.sv"
mkdir -p build/coverage

build_run () {  # $1=name $2=top $3=sources...
  local name=$1 top=$2; shift 2
  if [ -f "build/coverage/$name/coverage.dat" ]; then
    echo "=== [$name] SKIP (coverage.dat exists) ==="; return 0
  fi
  echo "=== [$name] ==="
  mkdir -p build/coverage/$name
  if verilator $VFLAGS --Mdir build/coverage/$name/obj --top-module $top "$@" $MAIN \
       -CFLAGS "-DVM_TOP_HDR=V${top}.h -DVM_TOP=V${top}" > build/coverage/$name/build.log 2>&1; then :; else
    (cd build/coverage/$name/obj 2>/dev/null && make -f V${top}.mk -j 2 >> ../build.log 2>&1) || true
  fi
  (cd build/coverage/$name && timeout 200 ./obj/V${top} > run.log 2>&1 || true)
  [ -f build/coverage/$name/coverage.dat ] && echo "  $name coverage.dat OK" || echo "  $name NO coverage.dat"
}

build_run tb_top        tb_top            $CPU_SRCS tb/cpu_tile_tb/tb_top.sv
build_run cpu_directed  cpu_directed_tb   $CPU_SRCS tb/cpu_tile_tb/cpu_directed_tb.sv
build_run noc           orca_noc_tb       rtl/common/orca_pkg.sv rtl/noc/*.sv tb/noc_tb/orca_noc_tb.sv
build_run ai_smoke      ai_tile_smoke_tb  $AI_SRCS tb/ai_tile_tb/ai_tile_smoke_tb.sv
build_run attn_smoke    attn_smoke_tb     $AI_SRCS tb/ai_tile_tb/attn_smoke_tb.sv
build_run cpu_crt       cpu_crt_tb        $CPU_SRCS tb/cpu_tile_tb/cpu_crt_tb.sv
build_run unit_coverage unit_coverage_tb  rtl/common/orca_pkg.sv rtl/cpu/execution/exu_fpu.sv rtl/cpu/execution/exu_crypto.sv rtl/cpu/execution/exu_bru.sv rtl/cpu/commit/cmt_trap.sv rtl/ai/ctrl/npu_dma.sv rtl/noc/orca_chi_coh.sv tb/cpu_tile_tb/unit_coverage_tb.sv
build_run unit_decode   unit_decode_tb    rtl/common/orca_pkg.sv rtl/cpu/decode/idu_decoder.sv rtl/cpu/decode/idu_rvc_expand.sv tb/cpu_tile_tb/unit_decode_tb.sv
build_run unit_exu      unit_exu_tb       rtl/common/orca_pkg.sv rtl/cpu/execution/exu_mul.sv rtl/cpu/execution/exu_vec.sv tb/cpu_tile_tb/unit_exu_tb.sv
build_run unit_dtlb    unit_dtlb_tb      rtl/common/orca_pkg.sv rtl/cpu/memory/lsu_dtlb.sv tb/cpu_tile_tb/unit_dtlb_tb.sv
build_run unit_cov2     unit_cov2_tb      rtl/common/orca_pkg.sv rtl/cpu/execution/exu_alu.sv rtl/cpu/rename/rnu_rat.sv rtl/cpu/commit/cmt_archreg.sv rtl/cpu/memory/lsu_mshr.sv rtl/cpu/memory/lsu_dcache.sv rtl/cpu/cache/dcache.sv rtl/noc/orca_noc_link.sv rtl/ai/noc/npu_tile_noc.sv tb/cpu_tile_tb/unit_cov2_tb.sv
build_run unit_lsu      unit_lsu_tb       rtl/common/orca_pkg.sv rtl/cpu/memory/lsu_st.sv tb/cpu_tile_tb/unit_lsu_tb.sv
build_run unit_attn     unit_attn_tb      rtl/common/orca_pkg.sv rtl/ai/attention/npu_attn_engine.sv tb/ai_tile_tb/unit_attn_tb.sv
build_run unit_hbm3     unit_hbm3_tb      rtl/common/orca_pkg.sv rtl/ai/memory/npu_hbm3_ctrl.sv tb/ai_tile_tb/unit_hbm3_tb.sv
build_run unit_systolic unit_systolic_tb  rtl/common/orca_pkg.sv rtl/ai/pe/npu_pe.sv rtl/ai/pe/npu_systolic.sv tb/ai_tile_tb/unit_systolic_tb.sv
build_run dtype         dtype_sweep_tb    rtl/common/orca_pkg.sv rtl/ai/pe/npu_pe.sv rtl/ai/pe/npu_acc.sv tb/ai_tile_tb/dtype_sweep_tb.sv
build_run lp            lp_coverage_tb    rtl/common/orca_pkg.sv rtl/common/clock_gate.sv rtl/soc/orca_pmu.sv tb/soc_tb/lp_coverage_tb.sv

# 對 randomized TB 自動多 seed (每 8 seed 累積合併, 收斂 toggle/FSM 殘點)
echo "=== multi-seed randomized TBs ==="
for tb in cpu_crt cpu_directed unit_exu unit_decode unit_systolic; do
  bin=$(ls build/coverage/$tb/obj/V* 2>/dev/null | head -1)
  if [ -n "$bin" ] && [ -f build/coverage/$tb/coverage.dat ]; then
    (cd build/coverage/$tb && for sd in 1 2 3 4 5 6 7 8; do
      ./obj/$(basename $bin) +seed=$((sd*2654435761)) > /dev/null 2>&1 || true
    done)
    echo "  $tb: 8 seeds merged ($(stat -c%s build/coverage/$tb/coverage.dat 2>/dev/null)B)"
  fi
done

echo "=== 合併 ==="
verilator_coverage -write coverage.dat build/coverage/*/coverage.dat
verilator_coverage -write-info coverage.info coverage.dat
python3 - << 'PYEOF'
data={};cur=None
for line in open("coverage.info"):
    line=line.rstrip("\n")
    if line.startswith("SF:"):cur=line[3:];data[cur]=[0,0]
    elif line.startswith("DA:"):
        p=line[3:].split(",")
        if len(p)>=2:
            data[cur][1]+=1
            if p[1].strip() not in ("0",""):data[cur][0]+=1
rows=[(v[0],v[1],k) for k,v in data.items() if v[1]>0]
rtl=[(h,t,k) for h,t,k in rows if '_tb' not in k]
th=sum(r[0] for r in rows);tt=sum(r[1] for r in rows)
rth=sum(r[0] for r in rtl);rtt=sum(r[1] for r in rtl)
full=[k for h,t,k in rows if h==t]
print(f"MERGED: {100*th/tt:.2f}% | RTL-only: {100*rth/rtt:.2f}% | {len(full)} at 100%")
PYEOF
