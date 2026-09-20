#=============================================================================
# ORCA v6.3 ZEN++ Build System Makefile
# File: Makefile
# Supports: VCS (Synopsys), Verilator (Open Source), Xcelium (Cadence)
#=============================================================================

# ---------------------------------------------------------------------------
# Project Configuration
# ---------------------------------------------------------------------------
PROJECT      := orca_v63
TOP_MODULE   := orca_v63_soc
RTL_DIR      := rtl
TB_DIR       := tb
OUT_DIR      := build
SIM_DIR      := $(OUT_DIR)/sim
SYN_DIR      := $(OUT_DIR)/syn
FPGA_DIR     := $(OUT_DIR)/fpga

# ---------------------------------------------------------------------------
# Source Files
# ---------------------------------------------------------------------------
PKG_SRCS     := $(RTL_DIR)/common/orca_pkg.sv

RTL_SRCS     := $(PKG_SRCS)                 $(RTL_DIR)/soc/orca_v63_soc.sv                 $(RTL_DIR)/cpu/orca_v63_cpu_tile.sv                 $(RTL_DIR)/cpu/orca_v63_cpu_core.sv                 $(RTL_DIR)/cpu/frontend/ifu_bpu.sv                 $(RTL_DIR)/cpu/frontend/ifu_fetch.sv                 $(RTL_DIR)/cpu/frontend/ifu_btb.sv                 $(RTL_DIR)/cpu/frontend/ifu_tlb.sv                 $(RTL_DIR)/cpu/decode/idu_decoder.sv                 $(RTL_DIR)/cpu/decode/idu_uop_queue.sv                 $(RTL_DIR)/cpu/decode/idu_rvc_expand.sv                 $(RTL_DIR)/cpu/rename/rnu_rat.sv                 $(RTL_DIR)/cpu/rename/rnu_freelist.sv                 $(RTL_DIR)/cpu/rename/rnu_remap.sv                 $(RTL_DIR)/cpu/scheduler/isu_int.sv                 $(RTL_DIR)/cpu/scheduler/isu_fp.sv                 $(RTL_DIR)/cpu/scheduler/isu_mem.sv                 $(RTL_DIR)/cpu/scheduler/isu_wake.sv                 $(RTL_DIR)/cpu/execution/exu_alu.sv $(RTL_DIR)/cpu/execution/prf.sv                 $(RTL_DIR)/cpu/execution/exu_mul.sv                 $(RTL_DIR)/cpu/execution/exu_fpu.sv                 $(RTL_DIR)/cpu/execution/exu_vec.sv                 $(RTL_DIR)/cpu/execution/exu_bru.sv                 $(RTL_DIR)/cpu/execution/exu_crypto.sv                 $(RTL_DIR)/cpu/memory/lsu_ld.sv                 $(RTL_DIR)/cpu/memory/lsu_st.sv                 $(RTL_DIR)/cpu/memory/lsu_dtlb.sv                 $(RTL_DIR)/cpu/memory/lsu_mshr.sv                 $(RTL_DIR)/cpu/memory/lsu_dcache.sv                 $(RTL_DIR)/cpu/cache/icache.sv                 $(RTL_DIR)/cpu/cache/dcache.sv                 $(RTL_DIR)/cpu/cache/l2cache.sv                 $(RTL_DIR)/cpu/cache/l3cache.sv                 $(RTL_DIR)/cpu/commit/cmt_rob.sv                 $(RTL_DIR)/cpu/commit/cmt_archreg.sv                 $(RTL_DIR)/cpu/commit/cmt_trap.sv                 $(RTL_DIR)/ai/orca_v63_ai_tile.sv                 $(RTL_DIR)/ai/ctrl/npu_gscu.sv                 $(RTL_DIR)/ai/ctrl/npu_dma.sv                 $(RTL_DIR)/ai/ctrl/npu_aix_intf.sv                 $(RTL_DIR)/ai/cluster/npu_cluster.sv                 $(RTL_DIR)/ai/cluster/npu_cu.sv                 $(RTL_DIR)/ai/pe/npu_systolic.sv                 $(RTL_DIR)/ai/pe/npu_pe.sv                 $(RTL_DIR)/ai/pe/npu_acc.sv                 $(RTL_DIR)/ai/attention/npu_attn_engine.sv                 $(RTL_DIR)/ai/memory/npu_l2_sram.sv                 $(RTL_DIR)/ai/memory/npu_hbm3_ctrl.sv                 $(RTL_DIR)/ai/memory/npu_hbm3_phy.sv                 $(RTL_DIR)/ai/noc/npu_tile_noc.sv                 $(RTL_DIR)/noc/orca_noc_router.sv                 $(RTL_DIR)/noc/orca_noc_link.sv $(RTL_DIR)/noc/orca_flit_adapter.sv                 $(RTL_DIR)/noc/orca_chi_coh.sv                 $(RTL_DIR)/noc/orca_bow_link.sv                 $(RTL_DIR)/pad/ddr5_ctrl.sv                 $(RTL_DIR)/pad/pcie_gen6.sv                 $(RTL_DIR)/pad/gpio_pad.sv

TB_SRCS      := $(TB_DIR)/orca_uvm_pkg.sv                 $(TB_DIR)/cpu_tile_tb/orca_cpu_agent.sv                 $(TB_DIR)/cpu_tile_tb/orca_cpu_sequence.sv                 $(TB_DIR)/cpu_tile_tb/orca_cpu_env.sv                 $(TB_DIR)/cpu_tile_tb/orca_cpu_test.sv                 $(TB_DIR)/cpu_tile_tb/tb_top.sv

ALL_SRCS     := $(RTL_SRCS) $(TB_SRCS)

# ---------------------------------------------------------------------------
# VCS (Synopsys) Configuration
# ---------------------------------------------------------------------------
VCS          := vcs
VCS_FLAGS    := -full64 -sverilog -ntb_opts uvm-1.2                 -timescale=1ns/1ps                 +v2k                 +acc+all                 -kdb -lca                 -debug_access+all                 -CFLAGS "-DVCS"                 -f $(OUT_DIR)/filelist.f                 -l $(OUT_DIR)/vcs_compile.log                 -o $(SIM_DIR)/simv

VCS_SIM      := $(SIM_DIR)/simv
VCS_SIM_FLAGS:= +UVM_VERBOSITY=UVM_MEDIUM                 +UVM_TESTNAME=orca_cpu_regression_test                 -l $(SIM_DIR)/sim.log

# ---------------------------------------------------------------------------
# Verilator (Open Source) Configuration
# ---------------------------------------------------------------------------
VERILATOR    := verilator
VERILATOR_FLAGS := --cc --exe --build --trace                    -Wall -Wno-UNOPTFLAT                    -Mdir $(OUT_DIR)/verilator                    --top-module $(TOP_MODULE)                    -f $(OUT_DIR)/filelist.f

# ---------------------------------------------------------------------------
# Xcelium (Cadence) Configuration
# ---------------------------------------------------------------------------
XCELIUM      := xrun
XCELIUM_FLAGS:= -sv -uvm                 -timescale 1ns/1ps                 -access +rwc                 -f $(OUT_DIR)/filelist.f                 -l $(OUT_DIR)/xcelium_compile.log

# ---------------------------------------------------------------------------
# Default Target
# ---------------------------------------------------------------------------
.PHONY: all clean vcs verilator xcelium sim wave lint filelist

all: filelist vcs

# ---------------------------------------------------------------------------
# File List Generation
# ---------------------------------------------------------------------------
filelist: $(OUT_DIR)/filelist.f

$(OUT_DIR)/filelist.f: $(ALL_SRCS)
	@mkdir -p $(OUT_DIR)
	@echo "Generating file list..."
	@for f in $(ALL_SRCS); do 		echo "$$f"; 	done > $@
	@echo "File list generated: $@"

# ---------------------------------------------------------------------------
# VCS Build
# ---------------------------------------------------------------------------
vcs: filelist
	@mkdir -p $(SIM_DIR)
	@echo "========================================"
	@echo "Building with VCS..."
	@echo "========================================"
	$(VCS) $(VCS_FLAGS)
	@echo "VCS build complete: $(VCS_SIM)"

# ---------------------------------------------------------------------------
# VCS Simulation
# ---------------------------------------------------------------------------
sim: vcs
	@mkdir -p $(SIM_DIR)
	@echo "========================================"
	@echo "Running VCS simulation..."
	@echo "========================================"
	cd $(SIM_DIR) && ./simv $(VCS_SIM_FLAGS)

# ---------------------------------------------------------------------------
# Waveform Viewing (DVE / Verdi)
# ---------------------------------------------------------------------------
wave:
	@if [ -f "$(SIM_DIR)/simv.vdb" ]; then 		verdi -dbdir $(SIM_DIR)/simv.vdb -ssf $(SIM_DIR)/waves.fsdb & 	elif [ -f "$(SIM_DIR)/waves.vcd" ]; then 		gtkwave $(SIM_DIR)/waves.vcd & 	else 		echo "No waveform file found. Run simulation first."; 	fi

# ---------------------------------------------------------------------------
# Verilator Build
# ---------------------------------------------------------------------------
verilator: filelist
	@mkdir -p $(OUT_DIR)/verilator
	@echo "========================================"
	@echo "Building with Verilator..."
	@echo "========================================"
	$(VERILATOR) $(VERILATOR_FLAGS)
	@echo "Verilator build complete"

# ---------------------------------------------------------------------------
# Xcelium Build
# ---------------------------------------------------------------------------
xcelium: filelist
	@mkdir -p $(SIM_DIR)
	@echo "========================================"
	@echo "Building with Xcelium..."
	@echo "========================================"
	$(XCELIUM) $(XCELIUM_FLAGS)
	@echo "Xcelium build complete"

# ---------------------------------------------------------------------------
# Lint (SpyGlass / Verilator)
# ---------------------------------------------------------------------------
lint: filelist
	@mkdir -p $(OUT_DIR)/lint
	@echo "========================================"
	@echo "Running Verilator lint..."
	@echo "========================================"
	$(VERILATOR) --lint-only -Wall -f $(OUT_DIR)/filelist.f 2>&1 | tee $(OUT_DIR)/lint/lint.log
	@echo "Lint complete: $(OUT_DIR)/lint/lint.log"

# ---------------------------------------------------------------------------
# Synthesis (Design Compiler)
# ---------------------------------------------------------------------------
syn:
	@mkdir -p $(SYN_DIR)
	@echo "========================================"
	@echo "Running Design Compiler synthesis..."
	@echo "========================================"
	dc_shell -f syn/cpu_tile.tcl | tee $(SYN_DIR)/dc.log
	@echo "Synthesis complete"

# ---------------------------------------------------------------------------
# FPGA Build
# ---------------------------------------------------------------------------
fpga:
	@mkdir -p $(FPGA_DIR)
	@echo "========================================"
	@echo "Running FPGA synthesis (Vivado)..."
	@echo "========================================"
	vivado -mode batch -source syn/fpga_build.tcl -log $(FPGA_DIR)/vivado.log
	@echo "FPGA build complete"

# ---------------------------------------------------------------------------
# Coverage Report
# ---------------------------------------------------------------------------
coverage:
	@if [ -d "$(SIM_DIR)/simv.vdb" ]; then 		urg -dir $(SIM_DIR)/simv.vdb -format both -report $(OUT_DIR)/coverage; 		echo "Coverage report: $(OUT_DIR)/coverage"; 	else 		echo "No coverage data found. Run simulation with coverage enabled."; 	fi

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(OUT_DIR)
	rm -rf csrc simv* *.vpd *.vcd ucli.key
	rm -rf verdiLog novas* *.log
	@echo "Clean complete"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo "ORCA v6.3 ZEN++ Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make all        - Generate filelist and build with VCS"
	@echo "  make vcs        - Compile with Synopsys VCS"
	@echo "  make sim        - Run VCS simulation"
	@echo "  make wave       - Open waveform viewer"
	@echo "  make verilator  - Compile with Verilator (open source)"
	@echo "  make xcelium    - Compile with Cadence Xcelium"
	@echo "  make lint       - Run static lint checks"
	@echo "  make syn        - Run Design Compiler synthesis"
	@echo "  make fpga       - Run FPGA synthesis (Vivado)"
	@echo "  make coverage   - Generate coverage report"
	@echo "  make clean      - Remove all build artifacts"
	@echo "  make help       - Show this help message"
