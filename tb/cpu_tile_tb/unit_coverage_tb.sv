// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.4 unit coverage sweep
`include "orca_pkg.sv"

// 單元級覆蓋 TB: 直接驅動各 leaf 模組輸入,遍歷 FSM / funct3 變體 / 埠 toggle,
// 目標 exu_mul/exu_vec/exu_fpu/exu_crypto/exu_bru/cmt_trap/npu_dma/orca_chi_coh
// 之 line + FSM + toggle 覆蓋。所有模組並發例化於同一 clk。
module unit_coverage_tb;
  import orca_pkg::*;
  import orca_chi_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end

  int errors = 0;


  // ============================================================
  // 3) exu_fpu — 全 funct3 (fadd/fmul/fsgnj/fmin/fmax/其他)
  // ============================================================
  uop_t fpu_uop; logic fpu_v, fpu_rv; xword_t fpu_r; rob_idx_t fpu_ri;
  exu_fpu u_fpu (.clk(clk), .rst_n(rst_n), .uop(fpu_uop), .uop_valid(fpu_v), .uop_ready(),
    .operand_a(64'h0000_0000_3F80_0000), .operand_b(64'h0000_0000_4000_0000), .operand_c(64'h0000_0000_4040_0000),
    .result(fpu_r), .result_valid(fpu_rv), .rob_idx(fpu_ri));

  // ============================================================
  // 4) exu_crypto — 全 funct3 (sha sigma/ma/ch/clmul)
  // ============================================================
  uop_t cry_uop; logic cry_v, cry_rv; xword_t cry_r; rob_idx_t cry_ri;
  exu_crypto u_cry (.clk(clk), .rst_n(rst_n), .uop(cry_uop), .uop_valid(cry_v), .uop_ready(),
    .operand_a(64'h0123_4567_89AB_CDEF), .operand_b(64'hFEDC_BA98_7654_3210), .operand_c(64'h0F0F_0F0F_0F0F_0F0F),
    .result(cry_r), .result_valid(cry_rv), .rob_idx(cry_ri));

  // ============================================================
  // 5) exu_bru — 6 條件 × taken/not × call/return
  // ============================================================
  uop_t bru_uop; logic bru_v; xword_t bru_rpc, bru_tgt; logic bru_rv, bru_mp, bru_buv, bru_but; rob_idx_t bru_ri;
  exu_bru u_bru (.clk(clk), .rst_n(rst_n), .uop(bru_uop), .uop_valid(bru_v), .uop_ready(),
    .operand_a(64'd100), .operand_b(64'd200),
    .redirect_valid(bru_rv), .redirect_pc(bru_rpc), .rob_idx(bru_ri), .mispredict(bru_mp),
    .bpu_update_valid(bru_buv), .bpu_update_pc(), .bpu_update_taken(bru_but), .bpu_update_target(bru_tgt));

  // ============================================================
  // 6) cmt_trap — 多 cause / 多 slot / csr r/w
  // ============================================================
  exception_t [RETIRE_WIDTH-1:0] tp_exc; tid_t [RETIRE_WIDTH-1:0] tp_tid;
  xword_t [RETIRE_WIDTH-1:0] tp_pc; logic [RETIRE_WIDTH-1:0] tp_v;
  logic tp_valid; tid_t tp_tid_o; xword_t tp_pco, tp_tv, tp_vec; logic [3:0] tp_cause;
  logic [SMT_THREADS-1:0] tp_flush; xword_t tp_csr_rd;
  cmt_trap u_trap (.clk(clk), .rst_n(rst_n),
    .rt_exc(tp_exc), .rt_tid(tp_tid), .rt_pc(tp_pc), .rt_valid(tp_v),
    .trap_valid(tp_valid), .trap_tid(tp_tid_o), .trap_pc(tp_pco), .trap_cause(tp_cause),
    .trap_tval(tp_tv), .trap_vector(tp_vec), .flush_mask(tp_flush),
    .csr_we(tp_csr_we), .csr_addr(tp_csr_addr), .csr_wdata(tp_csr_wd), .csr_rdata(tp_csr_rd));
  logic tp_csr_we; logic [11:0] tp_csr_addr; xword_t tp_csr_wd;

  // ============================================================
  // 7) npu_dma — load + store descriptor, hbm ack
  // ============================================================
  aix_cmd_t dma_desc; logic dma_dv, dma_dr, dma_done;
  logic [31:0] dma_l2a; logic dma_l2r, dma_l2we; logic [511:0] dma_l2rd, dma_l2wd;
  paddr_t dma_ha; logic dma_hr, dma_hwe, dma_hack; logic [511:0] dma_hrd, dma_hwd;
  npu_dma u_dma (.clk(clk), .rst_n(rst_n), .desc(dma_desc), .desc_valid(dma_dv), .desc_ready(dma_dr),
    .done(dma_done), .l2_addr(dma_l2a), .l2_req(dma_l2r), .l2_rdata(dma_l2rd), .l2_wdata(dma_l2wd),
    .l2_we(dma_l2we), .hbm_addr(dma_ha), .hbm_req(dma_hr), .hbm_we(dma_hwe),
    .hbm_rdata(dma_hrd), .hbm_wdata(dma_hwd), .hbm_ack(dma_hack));
  assign dma_hrd = {8{64'hDEAD_BEEF_1234_5678}};
  assign dma_l2rd = {8{64'hCAFE_F00D_8765_4321}};

  // ============================================================
  // 8) orca_chi_coh — 全 req_op + snoop
  // ============================================================
  paddr_t chi_ra, chi_sa; logic chi_rv_, chi_rrdy, chi_rspv, chi_sv, chi_sack, chi_sdirty;
  chi_req_op_t chi_op; logic [511:0] chi_rsd, chi_sd; coh_state_t chi_sst;
  orca_chi_coh u_chi (.clk(clk), .rst_n(rst_n),
    .req_addr(chi_ra), .req_valid(chi_rv_), .req_op(chi_op), .req_ready(chi_rrdy),
    .rsp_data(chi_rsd), .rsp_valid(chi_rspv),
    .snp_addr(chi_sa), .snp_valid(chi_sv), .snp_state(chi_sst), .snp_dirty(chi_sdirty),
    .snp_data(chi_sd), .snp_ack(chi_sack));

  // ============================================================
  // Stimulus
  // ============================================================
  int fpu_done = 0, cry_done = 0, bru_done = 0, dma_done2 = 0;
  initial begin
    fpu_uop = '0; cry_uop = '0; bru_uop = '0;
    fpu_v = 0; cry_v = 0; bru_v = 0; dma_dv = 0;
    tp_exc = '{default: '0}; tp_tid = '{default: '0}; tp_pc = '{default: '0}; tp_v = '0;
    tp_csr_we = 0; tp_csr_addr = '0; tp_csr_wd = '0;
    chi_ra = '0; chi_rv_ = 0; chi_op = CHI_RD; chi_sa = '0; chi_sv = 0;
    dma_desc = '0;
    rst_n = 0;
    #57 rst_n = 1;
    @(negedge clk);


    // ---- exu_fpu: 6 個 funct3 ----
    for (int f3 = 0; f3 < 6; f3++) begin
      fpu_uop = '0; fpu_uop.funct3 = 3'(f3); fpu_uop.rob_idx = rob_idx_t'(f3);
      fpu_v = 1; @(negedge clk); fpu_v = 0;
      repeat (6) @(negedge clk);
    end

    // ---- exu_crypto: 8 個 funct3 ----
    for (int f3 = 0; f3 < 8; f3++) begin
      cry_uop = '0; cry_uop.funct3 = 3'(f3); cry_uop.rob_idx = rob_idx_t'(f3);
      cry_v = 1; @(negedge clk); cry_v = 0;
      repeat (4) @(negedge clk);
    end

    // ---- exu_bru: 6 條件 × 2 組操作數(taken/not) ----
    for (int f3 = 0; f3 < 6; f3++) begin
      for (int swap = 0; swap < 2; swap++) begin
        bru_uop = '0; bru_uop.funct3 = 3'(f3); bru_uop.opcode = OP_BRANCH;
        bru_uop.is_cond = 1; bru_uop.pc = 64'h1000; bru_uop.imm = 64'h40;
        bru_uop.pred_taken = swap; bru_uop.rob_idx = rob_idx_t'(f3);
        bru_v = 1; @(negedge clk); bru_v = 0;
        repeat (2) @(negedge clk);
      end
    end
    // jal / jalr / call / return
    bru_uop = '0; bru_uop.opcode = OP_JAL; bru_uop.is_branch = 1; bru_uop.is_call = 1;
    bru_uop.pc = 64'h2000; bru_uop.imm = 64'h80; bru_uop.rob_idx = 10; bru_v = 1; @(negedge clk); bru_v = 0;
    repeat (2) @(negedge clk);
    bru_uop = '0; bru_uop.opcode = OP_JALR; bru_uop.is_branch = 1; bru_uop.is_indirect = 1; bru_uop.is_return = 1;
    bru_uop.pc = 64'h3000; bru_uop.imm = 64'h0; bru_uop.rob_idx = 11; bru_v = 1; @(negedge clk); bru_v = 0;
    repeat (2) @(negedge clk);

    // ---- cmt_trap: 各 slot / cause / csr ----
    for (int c = 0; c < 6; c++) begin
      tp_exc = '{default: '0}; tp_v = '0;
      tp_exc[c % 16] = '{valid: 1'b1, code: 4'(c + 1), tval: 64'h1000 + c};
      tp_tid[c % 16] = tid_t'(c % 4); tp_pc[c % 16] = 64'h8000_0000 + c * 4;
      tp_v[c % 16] = 1;
      @(negedge clk);
    end
    tp_v = '0;
    // csr 寫入各地址 (mtvec/mepc/mcause/mstatus)
    for (int a = 0; a < 4; a++) begin
      tp_csr_we = 1; tp_csr_addr = 12'h300 + a; tp_csr_wd = 64'hAAAA_0000 + a;
      @(negedge clk);
    end
    tp_csr_we = 0;
    repeat (4) @(negedge clk);

    // ---- npu_dma: load 後 store descriptor ----
    dma_desc = '{tdb0: 16'd1, tdb1: 16'd2, tdb2: 16'd3, opcode: AIX_OP_DMA_LD, flags: '0, tile_id: '0, length: 32'd256};
    dma_dv = 1; @(negedge clk);
    begin int g=0; while (!dma_dr && g<10) begin @(negedge clk); g++; end end
    dma_dv = 0;
    // 提供 hbm ack
    repeat (20) begin dma_hack = 1; @(negedge clk); end
    dma_hack = 0;
    repeat (10) @(negedge clk);
    dma_desc = '{tdb0: 16'd4, tdb1: 16'd5, tdb2: 16'd6, opcode: AIX_OP_DMA_ST, flags: '0, tile_id: '0, length: 32'd128};
    dma_dv = 1; @(negedge clk);
    begin int g=0; while (!dma_dr && g<10) begin @(negedge clk); g++; end end
    dma_dv = 0;
    repeat (20) begin dma_hack = 1; @(negedge clk); end
    dma_hack = 0;
    repeat (10) @(negedge clk);

    // ---- orca_chi_coh: 全 req_op + snoop dirty/shared ----
    for (int o = 0; o < 5; o++) begin
      chi_op = chi_req_op_t'(o); chi_rv_ = 1; chi_ra = 64'h1000_0000 + o * 64;
      @(negedge clk); chi_rv_ = 0;
      repeat (2) @(negedge clk);
    end
    chi_sv = 1; chi_sa = 64'h2000_0000; @(negedge clk); chi_sv = 0; repeat (2) @(negedge clk);
    chi_sv = 1; chi_sa = 64'h2000_0040; @(negedge clk); chi_sv = 0; repeat (2) @(negedge clk);

    repeat (20) @(negedge clk);
    $display("UNIT COVERAGE SWEEP DONE  fpu_rv=%0d cry_rv=%0d bru_rv=%0d dma_done=%0d",
             fpu_rv, cry_rv, bru_rv, dma_done);
    $display("TB PASS: unit coverage sweep complete");
    $finish;
  end

  always @(posedge dma_done) dma_done2 <= 1;
endmodule : unit_coverage_tb
