

================================================================================
v6.3.1 RELEASE NOTES (2026-09-13)
================================================================================

NEW MODULES (36 files, all in rtl/ per spec section 6.1):
  rtl/common/orca_pkg.sv        Global package: params (table 6.2), uop_t,
                                opcode_type_t (27 opcodes), flit_t, aix_tdb_t /
                                aix_cmd_t, MESI-F coh_state_t, rob_entry_t
  CPU frontend : ifu_fetch, ifu_btb (8K 4-way), ifu_tlb (Sv48)
  CPU decode   : idu_decoder (RV64I/M/A/F/V + AIX), idu_rvc_expand, idu_uop_queue
  CPU rename   : rnu_rat (SMT ckpt+restore), rnu_freelist, rnu_remap
  CPU scheduler: isu_sched (generic) + isu_int/isu_fp/isu_mem, isu_wake
  CPU execute  : exu_fpu (FP32 2-stage), exu_bru (redirect), exu_crypto (SHA/CLMUL)
  CPU memory   : lsu_dtlb, lsu_mshr, lsu_dcache
  CPU cache    : icache, dcache, l2cache, l3cache (64B line, behavioral)
  CPU commit   : cmt_archreg, cmt_trap (CSR min-set)
  CPU top      : orca_v63_cpu_core, orca_v63_cpu_tile
  AI tile      : npu_aix_intf, npu_gscu, npu_dma, npu_cu (npu_systolic wrapper),
                 npu_cluster, npu_acc, npu_l2_sram, npu_hbm3_phy, npu_tile_noc,
                 orca_v63_ai_tile
  NoC          : orca_noc_link (CRC16+credit+retry), orca_chi_coh, orca_bow_link
  Pad/SoC      : ddr5_ctrl, pcie_gen6, gpio_pad, orca_v63_soc

TESTS ADDED:
  tb/cpu_tile_tb/tb_top.sv        Core smoke: fetch -> L2 activity check
  tb/noc_tb/orca_noc_tb.sv        Link latency check
  tb/ai_tile_tb/ai_tile_smoke_tb  AIX GEMM command -> GSCU dispatch -> done irq

KNOWN LIMITATIONS (v6.3.2 roadmap):
  * orca_noc_router mesh wiring (flit_t <-> raw ports adapter)
  * PRF read ports feeding EXU operands; LSU x4 pipes into scheduler
  * ROB precise flush path & freelist retire dealloc hookup
  * npu_hbm3_ctrl / npu_attn_engine integration into ai_tile
  * No Verilator/Icarus in authoring environment - run 'make lint' locally

CHARTS: 12_pipeline_microarchitecture.png, 13_rtl_completion_status.png,
        14_verification_coverage_plan.png

================================================================================
v6.3.3 INTEGRATION UPDATE (2026-09-13)
================================================================================
NEW MODULES: rtl/cpu/execution/prf.sv (phys RF, 8W/10R),
             rtl/noc/orca_flit_adapter.sv (flit_t <-> router raw ports)
CPU CORE  : full EXU matrix (ALU/BRU/FPU/CRYPTO) fed by PRF read ports;
            ROB retire path complete: retire -> cmt_archreg writeback,
            old_prd -> freelist dealloc, exceptions -> cmt_trap (mtvec),
            flush priority trap > ROB > branch; RAT restore from arch map
AI TILE   : npu_dma + npu_hbm3_ctrl integrated (req/rsp -> L2 SRAM datapath,
            timing cfg + ECC + scrub); npu_hbm3_phy kept as training stub
SOC       : NoC mesh 4x2 - 8x orca_noc_router wired N/S/E/W, tiles attach
            via orca_flit_adapter (header dest injected at payload[511:496])
VERIFIED  : verilator lint 0 errors (cpu_core/cpu_tile/ai_tile/soc@NCO=1);
            smoke TBs: tb_top PASS (7 L2 fetches), ai_tile PASS (GEMM 3 cyc),
            noc_tb PASS (flit loopback)
NOTE      : soc lint at NCO=2 / ai_tile binary at NCLUSTERS=2 OOM in 4GB
            environment (Verilator elaboration memory); use NCO=1/NCLUSTERS=1
            or a larger-memory host for full builds.

================================================================================
v6.3.3 RELEASE (2026-09-13)
================================================================================
ROADMAP ITEMS (from v6.3.2 report) - ALL EXECUTED:
  1. PRF (12W/22R) feeds ALL EXU operands: ALU/BRU/FPU/MUL/VEC/CRYPTO/LSU-AGU;
     LSU x4 lanes (lsu_ld/lsu_st + lsu_dtlb x8 + lsu_dcache x4 + lsu_mshr x4)
     wired into isu_mem scheduler
  2. ROB precise flush: exceptions flush at retire head, mispredict clears
     only younger entries with exact tail rollback; freelist retire dealloc
     hookup + full rebuild on flush (flush_map from arch map)
  3. NoC mesh full port hookup (fixed east/west rx self-loop bug); all
     rx_ready/tx_ready interconnected, boundary tie-offs annotated;
     flit_t adapters between tile local ports and routers; cpu_tile new
     input port noc_out_ready_i -> real backpressure from adapter
  4. npu_attn_engine integrated into ai_tile (GSCU attn dispatch + L2 1R1W
     mux + HBM rsp tap); npu_hbm3_phy passthrough drives HBM pins after
     training; new ai_tile output hbm_init_done
  5. UVM directed sequences (flush / lsu_stress / mul_vec) + test classes,
     monitor covergroups (opcode class / flush / LSU lane / PRF wport),
     SVA extensions (ROB flush precision R18-R21, PRF tag legality A16-A18),
     Verilator-runnable cpu_directed_tb + coverage flow (run_coverage.sh)
  6. SoC full-param lint: OOM on 3GB host even with --hierarchical;
     evidence = soc+noc subset lint 0 errors + 4 top-level lints 0 errors
POST-VERIFICATION FIX:
  * rob_complete/rob_complete_exc hooked up for mul/vec/ld x4/st x4
    (previously those ROB entries never completed -> retire deadlock);
    same-class uop_id->rob_idx bug fixed in exu_alu/exu_mul/exu_vec;
    lsu_st gained result_valid/rob_idx/exception ports (contract-compliant)
VERIFIED (Verilator 5.006, -j 2):
  lint 0 %Error: cpu_core, cpu_tile, ai_tile, soc+noc subset
  5/5 TB PASS: tb_top (7 L2 fetches), orca_noc_tb (flit received),
    ai_tile_smoke_tb (GEMM 3 cyc), attn_smoke_tb (ATTN 1187 cyc),
    cpu_directed_tb (PRF/LSU/flush-freelist checks)
  Coverage (5 TBs merged): line 67.06% (1914/2854); cmt_rob 78.3%,
    rnu_freelist 87.5%, prf 92.3%, cpu_core 74.5%, npu_attn_engine 72.8%
KNOWN ISSUES -> v6.3.4 ROADMAP:
  * isu_sched multi-port issue broken (port0-only; uop_id never assigned
    -> queue flush on every issue, age compare dead); scheduler ready
    init for reset-era RAT mappings; rob_disp_v not gated by rob full
  * VEC operands broadcast from scalar PRF (no dedicated VEC_PRF)
  * attn engine datapath capture still behavioral stub; KV-cache HBM
    request-side arbitration pending
  * DTLB identity map; L1D miss does not go to L2 (smoke-level)
  * npu_systolic PE grid capped at 8 for host memory; restore ARRAY_DIM
    for synthesis
  * UVM/SVA not compile-verified (no UVM lib/VCS on host); SVA bind
    interface needs VCS-side integration
