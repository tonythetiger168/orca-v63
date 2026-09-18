#!/bin/bash
# Build & run all cov_f5 coverage TBs (verilator --coverage --cc --exe + cov_main)
set -e
COV_DIR="build/cov_f5"
COMMON_FLAGS="--coverage --cc --exe --build --timing -j 2 -Wno-fatal -Wno-BLKLOOPINIT -Irtl/common"
PKG="rtl/common/orca_pkg.sv"

mkdir -p ${COV_DIR}

build_run() { # $1=name $2=top $3=tb file $4=extra rtl srcs
    local NAME=$1 TOP=$2 TB=$3 SRCS=$4
    echo "== [COV-F5] build ${NAME} (${TOP}) =="
    mkdir -p ${COV_DIR}/${NAME}/obj
    verilator ${COMMON_FLAGS} --Mdir ${COV_DIR}/${NAME}/obj --top-module ${TOP} \
        ${PKG} ${SRCS} ${TB} $(pwd)/tb/cov_main.cpp \
        -CFLAGS "-DVM_TOP_HDR=V${TOP}.h -DVM_TOP=V${TOP}"
    echo "== [COV-F5] run ${NAME} =="
    (cd ${COV_DIR}/${NAME} && ./obj/V${TOP})
}

build_run link_retry  orca_noc_link_retry_tb  tb/cov_f5/orca_noc_link_retry_tb.sv  "rtl/noc/orca_noc_link.sv"
build_run router      orca_noc_router_cov_tb  tb/cov_f5/orca_noc_router_cov_tb.sv  "rtl/noc/orca_noc_router.sv"
build_run adapter     orca_flit_adapter_cov_tb tb/cov_f5/orca_flit_adapter_cov_tb.sv "rtl/noc/orca_flit_adapter.sv"
build_run bow         orca_bow_link_cov_tb    tb/cov_f5/orca_bow_link_cov_tb.sv    "rtl/noc/orca_bow_link.sv"
build_run chi         orca_chi_coh_cov_tb     tb/cov_f5/orca_chi_coh_cov_tb.sv     "rtl/noc/orca_chi_coh.sv"
build_run ddr5        ddr5_ctrl_cov_tb        tb/cov_f5/ddr5_ctrl_cov_tb.sv        "rtl/pad/ddr5_ctrl.sv"
build_run gpio        gpio_pad_cov_tb         tb/cov_f5/gpio_pad_cov_tb.sv         "rtl/pad/gpio_pad.sv"
build_run pcie        pcie_gen6_cov_tb        tb/cov_f5/pcie_gen6_cov_tb.sv        "rtl/pad/pcie_gen6.sv"

echo "== [COV-F5] merge (mine + baseline) =="
verilator_coverage --write-info ${COV_DIR}/merged.info \
    ${COV_DIR}/*/coverage.dat \
    /mnt/agents/output/coverage_baseline_v633/*/coverage.dat

echo "== [COV-F5] check my files =="
python3 - ${COV_DIR}/merged.info <<'PYEOF'
import sys
targets = [
  "rtl/noc/orca_noc_link.sv",
  "rtl/noc/orca_noc_router.sv",
  "rtl/noc/orca_flit_adapter.sv",
  "rtl/noc/orca_bow_link.sv",
  "rtl/noc/orca_chi_coh.sv",
  "rtl/pad/ddr5_ctrl.sv",
  "rtl/pad/gpio_pad.sv",
  "rtl/pad/pcie_gen6.sv",
]
sf = None
holes = {}
tot = {}
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line.startswith("SF:"):
            sf = line[3:]
        elif line.startswith("DA:") and sf:
            parts = line[3:].split(",")
            ln, hits = int(parts[0]), int(parts[1])
            for t in targets:
                if sf.endswith(t):
                    tot[t] = tot.get(t, 0) + 1
                    if hits == 0:
                        holes.setdefault(t, []).append(ln)
        elif line == "end_of_record":
            sf = None
ok = True
for t in targets:
    h = holes.get(t, [])
    n = tot.get(t, 0)
    if n == 0:
        print("MISSING(no points): %s" % t); ok = False
    elif h:
        print("HOLES %s: %s" % (t, h)); ok = False
    else:
        print("100%% (%d lines): %s" % (n, t))
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PYEOF
