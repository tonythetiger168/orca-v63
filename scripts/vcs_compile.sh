#!/bin/bash
#=============================================================================
# ORCA v6.3 ZEN++ VCS Compilation Script
# File: scripts/vcs_compile.sh
# Description: Standalone VCS compilation with full debug and coverage
#=============================================================================

set -e

PROJECT="orca_v63"
TOP="tb_top"
OUT_DIR="build/vcs"
FILELIST="build/filelist.f"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ORCA v6.3 VCS Compilation${NC}"
echo -e "${GREEN}========================================${NC}"

# Create output directory
mkdir -p ${OUT_DIR}
mkdir -p ${OUT_DIR}/waves
mkdir -p ${OUT_DIR}/coverage

# Check for filelist
if [ ! -f "${FILELIST}" ]; then
    echo -e "${YELLOW}Generating filelist...${NC}"
    make filelist
fi

# v6.3.3: orca_cpu_if.sv (UVM driver/monitor 介面) 與 tb_uvm_top.sv (UVM top)
# 未列於 Makefile TB_SRCS, 於此附加 filelist
# (interface 須在 orca_uvm_pkg.sv 之前編譯, 供 virtual interface 參考)
if ! grep -qx "tb/cpu_tile_tb/orca_cpu_if.sv" ${FILELIST}; then
    echo -e "${YELLOW}Appending tb/cpu_tile_tb/orca_cpu_if.sv to filelist...${NC}"
    sed -i '/^tb\/orca_uvm_pkg.sv$/i tb/cpu_tile_tb/orca_cpu_if.sv' ${FILELIST}
fi
if ! grep -qx "tb/cpu_tile_tb/tb_uvm_top.sv" ${FILELIST}; then
    echo -e "${YELLOW}Appending tb/cpu_tile_tb/tb_uvm_top.sv to filelist...${NC}"
    echo "tb/cpu_tile_tb/tb_uvm_top.sv" >> ${FILELIST}
fi

# VCS compilation flags
VCS_OPTS=""
VCS_OPTS+=" -full64"                    # 64-bit mode
VCS_OPTS+=" -sverilog"                 # SystemVerilog support
VCS_OPTS+=" -ntb_opts uvm-1.2"        # UVM 1.2
VCS_OPTS+=" -timescale=1ns/1ps"       # Default timescale
VCS_OPTS+=" +v2k"                     # Verilog-2001
VCS_OPTS+=" +acc+all"                 # Enable all PLI access
VCS_OPTS+=" -kdb -lca"                # Verdi debug database
VCS_OPTS+=" -debug_access+all"        # Full debug access
VCS_OPTS+=" -CFLAGS "-DVCS -O2""   # C compiler flags
VCS_OPTS+=" -f ${FILELIST}"           # Source file list
VCS_OPTS+=" -l ${OUT_DIR}/compile.log" # Compile log
VCS_OPTS+=" -o ${OUT_DIR}/simv"       # Output executable

# Coverage options (optional, enabled with +COVERAGE)
if [ "$1" == "+coverage" ]; then
    echo -e "${YELLOW}Enabling coverage collection...${NC}"
    VCS_OPTS+=" -cm line+cond+fsm+tgl+branch"  # Coverage types
    VCS_OPTS+=" -cm_dir ${OUT_DIR}/coverage"    # Coverage directory
    VCS_OPTS+=" -cm_name ${PROJECT}_cov"        # Coverage name
    VCS_OPTS+=" -cm_hier coverage.cfg"          # Coverage hierarchy config
fi

# Assertion options
VCS_OPTS+=" -assert enable_diag"       # Enable assertion diagnostics
VCS_OPTS+=" -assert vpiSeqBeginTime"   # Assertion timing

# Performance options
VCS_OPTS+=" -j8"                       # Parallel compilation (8 jobs)
VCS_OPTS+=" -fastcomp=2"              # Fast compilation mode
VCS_OPTS+=" -q"                       # Quiet mode (less verbose)

# X-propagation (for metastability analysis)
VCS_OPTS+=" -xprop=merge"

# Run compilation
echo -e "${YELLOW}Starting VCS compilation...${NC}"
echo "Command: vcs ${VCS_OPTS}"
vcs ${VCS_OPTS}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Compilation Successful!${NC}"
    echo -e "${GREEN}  Executable: ${OUT_DIR}/simv${NC}"
    echo -e "${GREEN}  Log: ${OUT_DIR}/compile.log${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  Compilation Failed!${NC}"
    echo -e "${RED}  Check: ${OUT_DIR}/compile.log${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi

# Generate compile summary
echo ""
echo -e "${GREEN}Compile Statistics:${NC}"
grep -E "(Error|Warning|Parsing|Elaborating)" ${OUT_DIR}/compile.log | tail -20
