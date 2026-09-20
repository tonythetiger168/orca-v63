// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.3.2 SVA 覆蓋率 TB - ROB (改造自 tb/cov_f3/f3_cmt_tb.sv, 原檔未動)
// DUT: cmt_rob (+ cmt_trap / cmt_archreg 保留原功能檢查)
//      + rnu_freelist (TB 實例, 供 R20/R21 freelist 觀察點)
// Checker: sva_rob_cov (22 顆 property 量測)
// 與 f3 差異:
//   (1) slot 11 保留給 keeper (前景只用 slot 0..10)
//   (2) keeper: 全 4 thread 維持 ROB 非空 (R16 ##[1:10] 視窗需求),
//       每 thread 只保留少量 entry 且「全部 complete」避免阻塞 retire
//   (3) phase B throttle 250 且 rob_full 時停送 (R7 後件需求)
//   (4) 新增 phase E: freelist 排空 (R21b 前提) 與補充 dealloc
//   (5) cmt_rob 已修復 retire 清 valid, 原 ghost-entry workaround 移除
`include "orca_pkg.sv"

module sva_rob_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  int errors = 0;
  localparam int ROB_PER_THREAD = ROB_ENTRIES / SMT_THREADS;

  // ======================= cmt_rob =======================
  uop_t      [DISPATCH_WIDTH-1:0] disp_uop;
  logic      [DISPATCH_WIDTH-1:0] disp_valid, disp_ready;
  rob_idx_t  [DISPATCH_WIDTH-1:0] disp_rob_idx;
  logic      [ROB_ENTRIES-1:0]    complete;
  xword_t    [ROB_ENTRIES-1:0]    complete_data;
  logic      [ROB_ENTRIES-1:0]    complete_exc;
  exception_t[ROB_ENTRIES-1:0]    complete_exc_code;
  logic                           br_mispredict;
  rob_idx_t                       br_mispredict_rob_idx;
  logic      [63:0]               br_mispredict_target_pc;
  rob_entry_t[RETIRE_WIDTH-1:0]   retire_entry;
  logic      [RETIRE_WIDTH-1:0]   retire_valid;
  logic                           retire_exception;
  exception_t                     retire_exc_code;
  logic      [63:0]               retire_exc_pc;
  logic                           flush_pipeline;
  logic      [63:0]               flush_redirect_pc;
  tid_t      [DISPATCH_WIDTH-1:0] disp_tid;
  tid_t      [RETIRE_WIDTH-1:0]   retire_tid;
  logic      [SMT_THREADS-1:0]    rob_full, rob_empty;
  logic      [$clog2(ROB_ENTRIES):0] rob_occupancy [SMT_THREADS];

  cmt_rob u_rob (.*);

  // ======================= rnu_freelist (R20/R21 觀察點) =======================
  logic [DECODE_WIDTH-1:0] fl_alloc_req;
  logic [RETIRE_WIDTH-1:0] fl_dealloc_req;
  phys_reg_idx_t [RETIRE_WIDTH-1:0] fl_dealloc_prd;
  phys_reg_idx_t fl_flush_map [32];
  logic          fl_empty;

  rnu_freelist u_fl (
    .clk(clk), .rst_n(rst_n),
    .alloc_req(fl_alloc_req), .alloc_prd(), .alloc_gnt(), .empty(fl_empty),
    .dealloc_req(fl_dealloc_req), .dealloc_prd(fl_dealloc_prd),
    .flush_valid(flush_pipeline), .flush_map(fl_flush_map));

  // retire -> freelist dealloc 鏡像 (同 cpu_core: rd!=0 才釋放 old_prd);
  // phase E 以 force 訊號注入 dealloc 恢復池
  logic [RETIRE_WIDTH-1:0] fl_dealloc_req_force = '0;
  phys_reg_idx_t [RETIRE_WIDTH-1:0] fl_dealloc_prd_force = '{default:'0};
  always_comb begin
    for (int i = 0; i < RETIRE_WIDTH; i++) begin
      fl_dealloc_req[i] = fl_dealloc_req_force[i] ||
                          (retire_valid[i] && (retire_entry[i].uop.rd != 0));
      fl_dealloc_prd[i] = fl_dealloc_req_force[i] ? fl_dealloc_prd_force[i]
                                                  : retire_entry[i].old_prd;
    end
    for (int a = 0; a < 32; a++) fl_flush_map[a] = phys_reg_idx_t'(a);
  end

  // ======================= cmt_trap (同 f3) =======================
  exception_t [RETIRE_WIDTH-1:0] t_exc;
  tid_t       [RETIRE_WIDTH-1:0] t_tid;
  xword_t     [RETIRE_WIDTH-1:0] t_pc;
  logic       [RETIRE_WIDTH-1:0] t_valid;
  logic trap_valid;  tid_t trap_tid;  xword_t trap_pc;
  logic [3:0] trap_cause;  xword_t trap_tval, trap_vector;
  logic [SMT_THREADS-1:0] flush_mask;
  logic csr_we;  logic [11:0] csr_addr;  xword_t csr_wdata, csr_rdata;

  cmt_trap u_trap (
    .clk(clk), .rst_n(rst_n),
    .rt_exc(t_exc), .rt_tid(t_tid), .rt_pc(t_pc), .rt_valid(t_valid),
    .trap_valid(trap_valid), .trap_tid(trap_tid), .trap_pc(trap_pc),
    .trap_cause(trap_cause), .trap_tval(trap_tval),
    .trap_vector(trap_vector), .flush_mask(flush_mask),
    .csr_we(csr_we), .csr_addr(csr_addr), .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata));

  // ======================= cmt_archreg (同 f3) =======================
  tid_t         [RETIRE_WIDTH-1:0] a_tid;
  arch_reg_idx_t[RETIRE_WIDTH-1:0] a_rda;
  phys_reg_idx_t[RETIRE_WIDTH-1:0] a_prd;
  xword_t       [RETIRE_WIDTH-1:0] a_data;
  logic         [RETIRE_WIDTH-1:0] a_valid, a_fp;
  phys_reg_idx_t cur_map [SMT_THREADS][32];
  tid_t dbg_tid;  arch_reg_idx_t dbg_rda;  logic dbg_fp;  xword_t dbg_rdata;

  cmt_archreg u_ag (
    .clk(clk), .rst_n(rst_n),
    .rt_tid(a_tid), .rt_rda(a_rda), .rt_prd(a_prd), .rt_data(a_data),
    .rt_valid(a_valid), .rt_fp(a_fp), .cur_map(cur_map),
    .dbg_tid(dbg_tid), .dbg_rda(dbg_rda), .dbg_fp(dbg_fp),
    .dbg_rdata(dbg_rdata));

  // ======================= SVA checker 銜接 =======================
  logic [ROB_ENTRIES-1:0] v_valid, v_complete, v_exception;
  tid_t w_flush_tid;
  always_comb begin
    for (int i = 0; i < ROB_ENTRIES; i++) begin
      v_valid[i]     = u_rob.rob_array[i].valid;
      v_complete[i]  = u_rob.rob_array[i].complete;
      v_exception[i] = u_rob.rob_array[i].exception;
    end
    if (u_rob.exception_detected) w_flush_tid = u_rob.exception_tid;
    else w_flush_tid = tid_t'(int'(br_mispredict_rob_idx) / ROB_PER_THREAD);
  end

  sva_rob_cov u_cov (
    .clk(clk), .rst_n(rst_n),
    .rob_array(u_rob.rob_array),
    .rob_valid(v_valid), .rob_complete(v_complete), .rob_exception(v_exception),
    .head(u_rob.head), .tail(u_rob.tail),
    .rob_full(rob_full), .rob_empty(rob_empty),
    .disp_valid(disp_valid), .disp_uop(disp_uop),
    .retire_valid(retire_valid), .retire_entry(retire_entry),
    .flush_valid(flush_pipeline), .flush_tid(w_flush_tid),
    .exception_detected(u_rob.exception_detected),
    .exception_rob_idx(u_rob.exception_rob_idx),
    .exception_tid(u_rob.exception_tid),
    .br_mispredict(br_mispredict),
    .br_mispredict_rob_idx(br_mispredict_rob_idx),
    .fl_free_cnt(16'(u_fl.cnt)), .fl_empty(fl_empty));

  // ---------------- helpers (同 f3) ----------------
  function automatic uop_t mk_uop(input tid_t t, input int pc, input logic br,
                                  input logic [63:0] im, input int uid);
    uop_t u;
    u = `UOP_NOP;
    u.opcode    = OP_ALU;
    u.pc        = 64'(pc);
    u.rd        = 5'd1;
    u.prd       = phys_reg_idx_t'(32 + (uid % 300));
    u.prd_old   = phys_reg_idx_t'(uid % 32);
    u.is_branch = br;
    u.imm       = im;
    u.tid       = t;
    u.uop_id    = 16'(uid);
    return u;
  endfunction

  task automatic rob_idle();
    disp_valid   = '0;
    complete     = '0;
    complete_exc = '0;
    br_mispredict = 1'b0;
  endtask

  // ---------------- keeper: 全 thread 維持非空 (R16) ----------------
  // 每拍輪詢一個 thread: occupancy==0 且 keeper_en 時以 slot 11 dispatch 一筆;
  // FIFO 最舊 entry 一律 complete (不保留 incomplete, 避免卡住 retire)。
  // flush 後 FIFO 以 valid bit 自我清理。
  rob_idx_t kfifo [SMT_THREADS][$];
  int kround = 0, kseq = 0;
  bit keeper_en = 0;
  bit keeper_no0 = 0;  // phase B 期間 keeper 不碰 thread0 (保持 t0 計數精確)

  // keeper 的 complete 脈衝只維持到下一次呼叫 (kprev 自清除):
  // 否則等待迴圈中 complete[idx] 跨拍殘留, entry 退休後仍被重打
  // complete -> invalid entry 上 stuck complete=1 (R5 違規源)
  rob_idx_t kprev_idx [SMT_THREADS];
  bit       kprev_v   [SMT_THREADS];

  task automatic keeper();
    // 清除上次呼叫留下的 complete 脈衝
    for (int q = 0; q < SMT_THREADS; q++)
      if (kprev_v[q]) begin complete[kprev_idx[q]] = 1'b0; kprev_v[q] = 0; end
    // 自我清理: 移除已被 flush/覆寫清掉的 entry
    for (int q = 0; q < SMT_THREADS; q++) begin
      while (kfifo[q].size() > 0 && !u_rob.rob_array[kfifo[q][0]].valid)
        void'(kfifo[q].pop_front());
    end
    // complete 各 thread 最舊 (valid 且未 complete 才打, 保護 R5)
    for (int q = 0; q < SMT_THREADS; q++) begin
      if (kfifo[q].size() > 0) begin
        automatic rob_idx_t idx = kfifo[q][0];
        if (u_rob.rob_array[idx].valid && !u_rob.rob_array[idx].complete) begin
          complete[idx]      = 1'b1;
          complete_data[idx] = 64'hD0_0000 + idx;
          kprev_idx[q] = idx; kprev_v[q] = 1'b1;
          void'(kfifo[q].pop_front());
        end
      end
    end
    // dispatch: 第一個空 thread 補一筆 (slot 11; 每拍呼叫 => 空窗 <=3 拍, R16)
    disp_valid[11] = 1'b0;
    for (int q = 0; q < SMT_THREADS; q++) begin
      if (!disp_valid[11] && keeper_en && !(keeper_no0 && q == 0) &&
          !fl_empty &&  // R21b: freelist 空時 keeper 也不得 dispatch
          u_rob.rob_occupancy[q] == 0) begin
        disp_valid[11] = 1'b1;
        disp_tid[11]   = tid_t'(q);
        disp_uop[11]   = mk_uop(tid_t'(q), 32'hA000 + kseq, 0, 0, 20000 + kseq);
        kseq++;
        #1;
        if (disp_ready[11]) kfifo[q].push_back(disp_rob_idx[11]);
        else disp_valid[11] = 1'b0;
      end
    end
  endtask

  // ---------------- main ----------------
  int dispatched0, retired_model, compl_upto, rob_base0, dbg_iter = 0, disp_start;
  int exc_flush_seen = 0;
  int brk_seen = 0;
  rob_idx_t exc_idx1, exc_idx2;

  initial begin
    $display("TB BOOT (sva_rob_tb)\n");    rob_idle();
    fl_alloc_req = '0;
    t_valid = '0;  t_exc = '{default:`EXC_NONE};
    t_tid = '{default:'0};  t_pc = '{default:'0};
    csr_we = 0;  csr_addr = 0;  csr_wdata = '0;
    a_valid = '0;  a_fp = '0;
    a_tid = '{default:'0};  a_rda = '{default:'0};
    a_prd = '{default:'0};  a_data = '{default:'0};
    dbg_tid = 0;  dbg_rda = 0;  dbg_fp = 0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);
    if (rob_empty !== 4'b1111) begin errors++; $display("ERR: rob not empty after reset"); end

    // ------------------------------------------------------------------
    $display("PHASE A start (同 f3: 4 thread 各 4 筆 dispatch+complete+retire)");
    // ------------------------------------------------------------------
    for (int c = 0; c < 4; c++) begin
      @(negedge clk);
      for (int i = 0; i < 4; i++) begin
        disp_valid[i] = 1'b1;
        disp_tid[i]   = tid_t'(i);
        disp_uop[i]   = mk_uop(tid_t'(i), 32'h1000 + c*16 + i, 0, 0, c*4+i);
      end
      #1;
      fl_alloc_req = '0;
      for (int i = 0; i < DECODE_WIDTH; i++)
        if (disp_valid[i] && disp_ready[i]) fl_alloc_req[i] = 1'b1;
    end
    @(negedge clk); rob_idle(); fl_alloc_req = '0;
    @(negedge clk);
    for (int t = 0; t < 4; t++)
      for (int e = 0; e < 4; e++) begin
        complete[t*256+e]      = 1'b1;
        complete_data[t*256+e] = 64'hA5_0000 + t*256+e;
      end
    @(negedge clk); complete = '0;
    repeat (3) @(negedge clk);
    if (rob_empty !== 4'b1111) begin errors++; $display("ERR: rob not drained"); end
    keeper_en  = 1;  // 之後所有等待迴圈皆呼叫 keeper() 維持非空
    keeper_no0 = 1;  // phase B: keeper 不插 thread0, 使 dispatched0/retired_model
                     // 只計 t0 (keeper 的 t1-3 插入/退休曾使 t0 在飛數峰值 <245,
                     // 導致 rob_full/R7/R17 從不觸發)

    // ------------------------------------------------------------------
    $display("PHASE B start (thread0 wrap, throttle 250, full 時停送)");
    // ------------------------------------------------------------------
    dispatched0 = 0; retired_model = 0; compl_upto = 0;
    rob_base0 = int'(u_rob.tail[0]);
    // 離開條件: 模型退休數達標, 或 t0 已全部 dispatch 且 ROB 排空
    // (retire_count_t0 抽樣可能漏計 boundary cycle, 以 occupancy 為準)
    while (retired_model < 290 &&
           !(dispatched0 >= 300 && u_rob.rob_occupancy[0] == 0)) begin
      @(negedge clk);
      disp_start = dispatched0;
      for (int i = 0; i < 11; i++) begin
        // full 時停送 (R7: dispatch to full 必須被拒/不發生)
        disp_valid[i] = (dispatched0 < 300) &&
                        ((dispatched0 - retired_model) < 250) && !rob_full[0];
        disp_tid[i]   = tid_t'(0);
        disp_uop[i]   = mk_uop(0, 32'h2000 + dispatched0 + i, 0, 0, 100+dispatched0+i);
      end
      keeper();
      #1;
      for (int i = 0; i < DISPATCH_WIDTH; i++)
        if (disp_valid[i] && disp_ready[i] && disp_tid[i] == 0) dispatched0++;
      // 先讓 250 筆無 complete 填滿 ROB (rob_full/R7/R17), 再開始補 complete
      for (int k = 0; k < 16 && compl_upto < disp_start && dispatched0 >= 250; k++) begin
        complete[(rob_base0 + compl_upto) % 256]      = 1'b1;
        complete_data[(rob_base0 + compl_upto) % 256] = 64'hB0_0000 + compl_upto;
        compl_upto++;
      end
      fl_alloc_req = '0;
      for (int i = 0; i < DECODE_WIDTH; i++)
        if (disp_valid[i] && disp_ready[i]) fl_alloc_req[i] = 1'b1;
      #1 retired_model += retire_count_t0();
      @(posedge clk);
      #1 complete = '0; fl_alloc_req = '0;
      if (dbg_iter > 600) begin $display("ERR: phase B timeout"); errors++; break; end
      dbg_iter++;
    end
    // 補齊剩餘 complete, 等 drain (修復後 retire 正常停在 tail)
    @(negedge clk);
    for (int i = 0; i < 11; i++) disp_valid[i] = '0;
    keeper();
    for (int k = compl_upto; k < dispatched0; k++)
      complete[(rob_base0 + k) % 256] = 1'b1;
    @(posedge clk); #1 complete = '0;
    // 等 thread0 排空 head==tail (keeper 會再補, 故等 occupancy<=2 即可)
    dbg_iter = 0;
    while (u_rob.rob_occupancy[0] > 2 && dbg_iter < 60) begin
      @(negedge clk); keeper(); dbg_iter++;
    end
    if (u_rob.rob_occupancy[0] > 2) begin
      errors++; $display("ERR: phase B drain occ=%0d", u_rob.rob_occupancy[0]);
    end
    keeper_no0 = 0;  // 恢復 keeper 全 thread (phase C/D 等待迴圈需要)
    repeat (2) begin @(negedge clk); keeper(); end
    if (!rob_full_seen) begin errors++; $display("ERR: rob_full never asserted"); end

    // ------------------------------------------------------------------
    $display("PHASE C start (例外於 retire 頭端, 兩 thread)");
    // ------------------------------------------------------------------
    @(negedge clk); keeper();
    disp_valid[0] = 1; disp_tid[0] = 1; disp_uop[0] = mk_uop(1, 32'h3000, 0, 0, 500);
    disp_valid[1] = 1; disp_tid[1] = 2; disp_uop[1] = mk_uop(2, 32'h4000, 0, 0, 501);
    disp_valid[2] = 1; disp_tid[2] = 3; disp_uop[2] = mk_uop(3, 32'h5000, 0, 0, 502);
    #1 exc_idx1 = disp_rob_idx[0]; exc_idx2 = disp_rob_idx[1];
    @(negedge clk); rob_idle(); keeper();
    @(negedge clk); keeper();
    // 等 t1/t2 的例外 entry 到達 head (keeper 舊 entry 先退休)
    complete[exc_idx1] = 1; complete_exc[exc_idx1] = 1;
    complete_exc_code[exc_idx1] = '{valid:1'b1, code:4'd2, tval:64'hDEAD};
    complete[exc_idx2] = 1; complete_exc[exc_idx2] = 1;
    complete_exc_code[exc_idx2] = '{valid:1'b1, code:4'd3, tval:64'hBEEF};
    @(negedge clk); complete = '0; complete_exc = '0; keeper();
    dbg_iter = 0;
    while ((!exc_flush_seen || !ret_exc_seen) && dbg_iter < 40) begin
      @(negedge clk); keeper(); dbg_iter++;
    end
    if (!exc_flush_seen) begin errors++; $display("ERR: exception flush not seen"); end
    if (!ret_exc_seen)  begin errors++; $display("ERR: retire_exception not seen"); end
    repeat (3) begin @(negedge clk); keeper(); end

    // ------------------------------------------------------------------
    $display("PHASE D start (branch mispredict at retire + 精確 br flush)");
    // ------------------------------------------------------------------
    @(negedge clk); keeper();
    disp_valid[0] = 1; disp_tid[0] = 0; disp_uop[0] = mk_uop(0, 32'h6000, 1, 64'h1, 600);
    disp_valid[1] = 1; disp_tid[1] = 0; disp_uop[1] = mk_uop(0, 32'h6004, 0, 0, 601);
    #1 exc_idx1 = disp_rob_idx[0];
    @(negedge clk); rob_idle(); keeper();
    @(negedge clk); keeper();
    complete[exc_idx1] = 1;
    @(negedge clk); complete = '0; keeper();
    dbg_iter = 0;
    while (!brk_seen && dbg_iter < 40) begin
      @(negedge clk); keeper(); dbg_iter++;
    end
    if (!brk_seen) begin errors++; $display("ERR: branch-at-retire break not seen"); end
    // 精確 branch flush (R19)
    @(negedge clk); keeper();
    br_mispredict = 1'b1;
    br_mispredict_rob_idx = exc_idx1;
    br_mispredict_target_pc = 64'h7000;
    @(negedge clk); br_mispredict = 1'b0; keeper();
    repeat (3) begin @(negedge clk); keeper(); end

    // ------------------------------------------------------------------
    $display("PHASE E start (freelist 排空 -> R21b, 再補 dealloc)");
    // ------------------------------------------------------------------
    keeper_en = 1;   // drain 期間 keeper 維持各 thread 非空 (R16 ##[1:10] 視窗)
    @(negedge clk); rob_idle(); keeper();
    // 排空 freelist (ROB dispatch 不伴隨 fl_alloc, 互不干擾)
    dbg_iter = 0;
    while (!fl_empty && dbg_iter < 400) begin
      fl_alloc_req = '1;   // 6 alloc/拍 (純 freelist, 無 ROB dispatch)
      @(negedge clk); keeper();
      dbg_iter++;
    end
    fl_alloc_req = '0;
    if (!fl_empty) begin errors++; $display("ERR: freelist never empty"); end
    // 全空靜止窗壓至最短 (<R16 的 10 拍): R21b 累積 attempts (fl_empty && !disp)
    keeper_en = 0;
    rob_idle();  // 清掉 keeper 最後一筆 kprev complete, 避免跨拍殘留 (R5)
    repeat (1) @(negedge clk);  // fl_empty 窗壓至最短 (R21b attempts=2 足夠);
                                // R16: 空前 streak<=5 + 1 + 1(dealloc) + keeper 恢復 <=10
    // 第 1 拍 dealloc 時 keeper 仍關 (fl_empty 本拍解除), 之後恢復 keeper
    @(negedge clk);
    for (int i = 0; i < RETIRE_WIDTH; i++) begin
      fl_dealloc_req_force[i] = 1'b1;
      fl_dealloc_prd_force[i] = phys_reg_idx_t'(32 + i);
    end
    keeper_en = 1;
    for (int k = 1; k < 8; k++) begin
      @(negedge clk); keeper();
      for (int i = 0; i < RETIRE_WIDTH; i++) begin
        fl_dealloc_req_force[i] = 1'b1;
        fl_dealloc_prd_force[i] = phys_reg_idx_t'(32 + k*16 + i);
      end
    end
    @(negedge clk); keeper();
    for (int i = 0; i < RETIRE_WIDTH; i++) fl_dealloc_req_force[i] = 1'b0;
    // freeze: 每 thread 無條件補一筆永不 complete 的 entry (同拍 4 slot 一次到位),
    // 使 TRAP/ARCHREG 期間 rob_empty 恆 0 — 不能只補空 thread: 非空 thread 手上
    // 的 entry 可能已被 keeper complete, freeze 後無人再補, retire 掉就長空 (R16)
    keeper_en = 0;
    @(negedge clk); rob_idle();
    for (int t = 0; t < SMT_THREADS; t++) begin
      disp_valid[8+t] = 1'b1;
      disp_tid[8+t]   = tid_t'(t);
      disp_uop[8+t]   = mk_uop(tid_t'(t), 32'hE000 + t, 0, 0, 30000 + t);
    end
    @(negedge clk); rob_idle();

    // ------------------------------------------------------------------
    $display("TRAP start (同 f3)");
    // ------------------------------------------------------------------
    @(negedge clk);
    csr_addr = 12'h305; #1;
    if (csr_rdata !== 64'h0) begin errors++; $display("ERR: mtvec reset"); end
    csr_addr = 12'h300; #1;
    if (csr_rdata !== 64'h8) begin errors++; $display("ERR: mstatus reset"); end
    csr_addr = 12'h341; #1;
    csr_addr = 12'h342; #1;
    csr_addr = 12'h999; #1;
    if (csr_rdata !== 64'h0) begin errors++; $display("ERR: csr default"); end
    csr_we = 1; csr_addr = 12'h305; csr_wdata = 64'h8000_0040;
    @(negedge clk);
    csr_addr = 12'h300; csr_wdata = 64'hF;
    @(negedge clk);
    csr_addr = 12'h341; csr_wdata = 64'h1234;
    @(negedge clk);
    csr_we = 0; csr_addr = 12'h305; #1;
    if (csr_rdata !== 64'h8000_0040) begin errors++; $display("ERR: mtvec rw"); end
    @(negedge clk);
    t_valid[0] = 1; t_tid[0] = 1; t_pc[0] = 64'h1110;
    t_exc[0] = '{valid:1'b1, code:4'd11, tval:64'hAAAA};
    #1;
    if (!trap_valid || trap_tid !== 1 || trap_cause !== 4'd11)
      begin errors++; $display("ERR: trap basic"); end
    if (flush_mask !== 4'b0010) begin errors++; $display("ERR: flush_mask"); end
    if (trap_vector !== 64'h8000_0040) begin errors++; $display("ERR: trap_vector"); end
    @(negedge clk);
    t_valid = '0; t_exc[0] = `EXC_NONE;
    @(negedge clk);
    t_valid[3] = 1; t_tid[3] = 2; t_pc[3] = 64'h2220;
    t_exc[3] = '{valid:1'b1, code:4'd8, tval:64'h1};
    t_valid[7] = 1; t_tid[7] = 3; t_pc[7] = 64'h3330;
    t_exc[7] = '{valid:1'b1, code:4'd9, tval:64'h2};
    #1;
    if (!trap_valid || trap_tid !== 2 || trap_pc !== 64'h2220)
      begin errors++; $display("ERR: trap priority sel"); end
    @(negedge clk); t_valid = '0;
    @(negedge clk);
    csr_addr = 12'h341; #1;
    csr_addr = 12'h342; #1;
    csr_addr = 12'h300; #1;
    if (csr_rdata[3] !== 1'b0) begin errors++; $display("ERR: mstatus mie clear"); end
    @(negedge clk);

    // ------------------------------------------------------------------
    $display("ARCHREG start (同 f3)");
    // ------------------------------------------------------------------
    @(negedge clk);
    for (int i = 0; i < 4; i++) begin
      a_valid[i] = 1; a_tid[i] = tid_t'(i % 2);
      a_rda[i] = 5'(i + 1); a_prd[i] = phys_reg_idx_t'(32 + i);
      a_data[i] = 64'hC0_0000 + i; a_fp[i] = (i % 2 == 1);
    end
    a_valid[4] = 1; a_tid[4] = 0; a_rda[4] = 5'd0; a_data[4] = 64'hFFFF; a_fp[4] = 0;
    @(negedge clk);
    a_valid = '0;
    dbg_tid = 0; dbg_rda = 5'd1; dbg_fp = 0; #1;
    if (dbg_rdata !== 64'hC0_0000) begin errors++; $display("ERR: archreg int rd"); end
    dbg_tid = 1; dbg_rda = 5'd2; dbg_fp = 1; #1;
    if (dbg_rdata !== 64'hC0_0001) begin errors++; $display("ERR: archreg fp rd"); end
    dbg_tid = 0; dbg_rda = 5'd0; dbg_fp = 0; #1;
    if (dbg_rdata !== 64'h0) begin errors++; $display("ERR: x0 not zero"); end
    dbg_tid = 3; dbg_rda = 5'd31; dbg_fp = 1; #1;
    @(negedge clk);

    repeat (4) @(negedge clk);
    // ---- SVA checker 結果併入 PASS 判定 ----
    for (int i = 0; i < 22; i++) begin
      if (u_cov.att[i] < 1) begin
        errors++; $display("ERR: SVA property %0d (%s) vacuous", i, u_cov.PNAME[i]);
      end
      if (u_cov.fail[i] != 0) begin
        errors++; $display("ERR: SVA property %0d (%s) fails=%0d", i, u_cov.PNAME[i], u_cov.fail[i]);
      end
    end
    if (errors == 0) $display("SVA_ROB_TB PASS");
    else             $display("SVA_ROB_TB FAIL errors=%0d", errors);
    $finish;
  end

  // ---------------- monitors (同 f3) ----------------
  logic rob_full_seen = 0;
  logic ret_exc_seen  = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (|rob_full) rob_full_seen <= 1'b1;
      if (retire_exception) ret_exc_seen <= 1'b1;
      if (flush_pipeline && flush_redirect_pc == 64'h8000_0000) exc_flush_seen <= 1;
      for (int t = 0; t < SMT_THREADS; t++) begin
        automatic rob_idx_t h = u_rob.thread_base(tid_t'(t)) + u_rob.head[t];
        if (u_rob.rob_array[h].valid && u_rob.rob_array[h].complete &&
            u_rob.rob_array[h].uop.is_branch &&
            (u_rob.rob_array[h].branch_taken != u_rob.rob_array[h].uop.imm[0]))
          brk_seen <= 1;
      end
    end
  end

  function automatic int retire_count_dbg();
    int c = 0;
    for (int i = 0; i < RETIRE_WIDTH; i++) if (retire_valid[i]) c++;
    return c;
  endfunction

  // phase B 專用: 只計 thread0 退休 (keeper 的 t1-3 退休不計入 throttle)
  function automatic int retire_count_t0();
    int c = 0;
    for (int i = 0; i < RETIRE_WIDTH; i++)
      if (retire_valid[i] && retire_tid[i] == 0) c++;
    return c;
  endfunction

endmodule : sva_rob_tb
