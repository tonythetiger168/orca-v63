#!/bin/bash
#=============================================================================
# ORCA v6.3.3 Verilator Coverage Runner
# File: scripts/run_coverage.sh
# Description: 以 verilator --coverage --binary --timing 建置並執行 5 個 TB
#   (tb_top / orca_noc_tb / ai_tile_smoke_tb / attn_smoke_tb / cpu_directed_tb),
#   再用 verilator_coverage 彙總, 輸出 build/coverage/summary.txt
# 用法: bash scripts/run_coverage.sh
#=============================================================================

set -e

COV_DIR="build/coverage"
# 註: Verilator 5.006 --binary 不會自動寫 coverage.dat, 改用 --cc --exe
#     + tb/cov_main.cpp (結束時呼叫 VerilatedCov::write)
COMMON_FLAGS="--coverage --cc --exe --build --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT -Irtl/common"

CPU_SRCS="rtl/common/orca_pkg.sv rtl/cpu/orca_v63_cpu_core.sv \
  rtl/cpu/frontend/*.sv rtl/cpu/decode/*.sv rtl/cpu/rename/*.sv \
  rtl/cpu/scheduler/*.sv rtl/cpu/execution/*.sv rtl/cpu/memory/*.sv \
  rtl/cpu/cache/*.sv rtl/cpu/commit/*.sv"
NOC_SRCS="rtl/common/orca_pkg.sv rtl/noc/*.sv"
AI_SRCS="rtl/common/orca_pkg.sv rtl/ai/orca_v63_ai_tile.sv rtl/ai/ctrl/*.sv \
  rtl/ai/cluster/*.sv rtl/ai/pe/*.sv rtl/ai/attention/*.sv rtl/ai/memory/*.sv \
  rtl/ai/noc/*.sv rtl/noc/orca_flit_adapter.sv"

mkdir -p ${COV_DIR}

build_run() { # $1=name $2=top $3=tb file $4=srcs
    local NAME=$1 TOP=$2 TB=$3 SRCS=$4
    echo "== [COV] build ${NAME} (${TOP}) =="
    mkdir -p ${COV_DIR}/${NAME}
    verilator ${COMMON_FLAGS} --Mdir ${COV_DIR}/${NAME}/obj --top-module ${TOP} \
        ${SRCS} ${TB} $(pwd)/tb/cov_main.cpp \
        -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}"
    echo "== [COV] run ${NAME} =="
    (cd ${COV_DIR}/${NAME} && ./obj/V${TOP})   # cov_main 於 CWD 寫 coverage.dat
}

build_run tb_top        tb_top           tb/cpu_tile_tb/tb_top.sv          "${CPU_SRCS}"
build_run cpu_directed  cpu_directed_tb  tb/cpu_tile_tb/cpu_directed_tb.sv "${CPU_SRCS}"
build_run noc           orca_noc_tb      tb/noc_tb/orca_noc_tb.sv          "${NOC_SRCS}"
build_run ai_smoke      ai_tile_smoke_tb tb/ai_tile_tb/ai_tile_smoke_tb.sv "${AI_SRCS}"
build_run attn_smoke    attn_smoke_tb    tb/ai_tile_tb/attn_smoke_tb.sv    "${AI_SRCS}"

echo "== [COV] merge =="
verilator_coverage --write ${COV_DIR}/merged.dat ${COV_DIR}/*/coverage.dat
verilator_coverage --write-info ${COV_DIR}/coverage.info ${COV_DIR}/*/coverage.dat

echo "== [COV] summary =="
python3 - ${COV_DIR} <<'PYEOF'
import sys, os, re, datetime

cov_dir = sys.argv[1]
info = os.path.join(cov_dir, "coverage.info")

total_lf = total_lh = 0
per_file = []
sf = None
lf = lh = 0
with open(info) as f:
    for line in f:
        line = line.strip()
        if line.startswith("SF:"):
            sf = line[3:]; lf = lh = 0
        elif line.startswith("DA:"):
            parts = line[3:].split(",")
            if len(parts) >= 2:
                lf += 1
                if int(parts[1]) > 0: lh += 1
        elif line == "end_of_record" and sf is not None:
            per_file.append((sf, lh, lf))
            total_lf += lf; total_lh += lh
            sf = None

pct = (100.0 * total_lh / total_lf) if total_lf else 0.0

# --- Toggle coverage: 解析 merged.dat (C '<keys>page v_toggle/<sig>' <hits>) ---
tgl_hit = tgl_total = 0
per_file_tgl = {}
dat = os.path.join(cov_dir, "merged.dat")
cre = re.compile(r"^C '(.*)' (\d+)$")
if os.path.exists(dat):
    with open(dat, errors="replace") as f:
        for line in f:
            m = cre.match(line.rstrip("\n"))
            if not m: continue
            keys, hits = m.group(1), int(m.group(2))
            # key 格式: <soh>f<soh><file><soh>l<soh>...<soh>page<soh>v_toggle/...
            km = re.search(r"\x01f\x02([^\x01]+)\x01", keys)
            fname = km.group(1) if km else "?"
            if "v_toggle" not in keys: continue
            tgl_total += 1
            per_file_tgl.setdefault(fname, [0, 0])
            per_file_tgl[fname][1] += 1
            if hits > 0:
                tgl_hit += 1
                per_file_tgl[fname][0] += 1
tgl_pct = (100.0 * tgl_hit / tgl_total) if tgl_total else 0.0

out = []
out.append("ORCA v6.3.3 Verilator Coverage Summary")
out.append("Generated: " + datetime.datetime.now().isoformat(timespec="seconds"))
out.append("Tool: verilator 5.006 --coverage --cc --exe --timing + verilator_coverage")
out.append("TBs: tb_top, cpu_directed_tb, orca_noc_tb, ai_tile_smoke_tb, attn_smoke_tb")
out.append("")
out.append("== Line coverage (per source file) ==")
per_file.sort(key=lambda x: (x[2] and (100.0*x[1]/x[2])))
for sf, lh, lf in per_file:
    p = (100.0*lh/lf) if lf else 0.0
    out.append("  %6.2f%%  %6d/%-6d  %s" % (p, lh, lf, sf))
out.append("")
out.append("== Total line coverage ==")
out.append("  Lines covered: %d / %d (%.2f%%)" % (total_lh, total_lf, pct))
out.append("")
out.append("== Total toggle coverage (from merged.dat, per-bit points) ==")
out.append("  Toggle points covered: %d / %d (%.2f%%)" % (tgl_hit, tgl_total, tgl_pct))
out.append("")
out.append("== Toggle coverage (per source file, top 20 by points) ==")
for fname, (h, t) in sorted(per_file_tgl.items(), key=lambda kv: -kv[1][1])[:20]:
    p = (100.0*h/t) if t else 0.0
    out.append("  %6.2f%%  %6d/%-6d  %s" % (p, h, t, fname))

text = "\n".join(out) + "\n"
with open(os.path.join(cov_dir, "summary.txt"), "w") as f:
    f.write(text)
print(text)
PYEOF

echo "== [COV] done: ${COV_DIR}/summary.txt =="
