// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.3
// cpu_directed_tb: Verilator 可執行之 directed 測試 (對應 UVM orca_cpu_flush_seq /
// orca_cpu_lsu_stress_seq / orca_cpu_mul_vec_seq 的本機驗收版本)
//
// 直接例化 orca_v63_cpu_core (風格同 tb_top.sv), L2 fill 餵固定程式
// (所有位址皆回同一 pattern, 每 8 word 為一組):
//   0: addi x1,x0,32   1: addi x2,x0,64   2: mul x3,x0,x0   3: mul x4,x0,x0
//   4: sw  x0,0(x0)    5: lw  x5,0(x0)    6: add x6,x0,x0   7: sw x0,32(x0)
// 所有 uop 來源皆為 x0 (排程器 insert 時即 ready, 不需等待喚醒),
// 保證可發射到 ALU/MUL/LSU, 產生真實 PRF 寫入與 LSU lane 活動。
// 兩個連續 mul: 保證 isu_fp 每拍有 uop 可發射。
// 註: isu_sched 目前每拍只發射最老者到 port0 (=> exu_vec 執行, prf_wv[4]);
//     port1 (exu_mul, prf_wv[3]) 因排程器選擇邏輯不可達 — 已回報為 RTL 問題,
//     故本 TB 以 exu_vec 寫回驗證 fp 排程路徑的 PRF 寫入活動。
//
// flush 採「強制注入」(任務允許): 每 INJ_PERIOD 拍 force 一拍
// dut.bru_mispredict + bru_rob_idx(=head[0]) + bru_redir_pc,
// 觸發 cmt_rob 精確 flush (清年輕 entry + tail 回捲) 與
// rnu_freelist 全量重建, 之後 release, 管線恢復繼續執行。
//
// 檢查 (hierarchical 探針):
//   (a) dut.prf_wv  — PRF 12 寫埠有寫入活動 (含 mul wport3 / ld wport5+)
//   (b) dut.mis_v   — isu_mem LSU lane 有 issue 活動
//   (c) dut.rob_flush_v 觀察到 flush; flush 後 ROB valid popcount 下降,
//       freelist (dut.u_remap.u_fl.cnt) 重建且數量守恆 (不低於 flush 前,
//       不超過 POOL-32), 且 flush 後 PRF 活動恢復
`include "orca_pkg.sv"

module cpu_directed_tb;
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_6332;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  paddr_t l2a; logic l2v;
  logic [511:0] l2l; logic l2f; logic halt;
  tid_t tid;
  orca_v63_cpu_core dut (
    .clk(clk), .rst_n(rst_n), .tid(tid),
    .l2_req_addr(l2a), .l2_req_valid(l2v),
    .l2_fill_line(l2l), .l2_fill_valid(l2f), .core_halt(halt));

  // ---------------- 程式 (8 words 一組, 512b line 放兩份) ----------------
  localparam logic [31:0] PROG [8] = '{
    32'h0200_0093,  // 0: addi x1, x0, 32
    32'h0400_0113,  // 1: addi x2, x0, 64
    32'h0200_01B3,  // 2: mul  x3, x0, x0  (落 isu_fp port0 -> exu_vec, 不計)
    32'h0200_42B3,  // 3: div  x5, x1, x0  (32/0 除零 -> exu_mul exception -> cmt_rob 異常/flush)
    32'h0000_2023,  // 4: sw   x0, 0(x0)
    32'h0000_2283,  // 5: lw   x5, 0(x0)
    32'h0200_0657,  // 6: vadd.vv v12,v0,v0  (OP_VEC -> isu_fp port0 -> exu_vec 寫回)
    32'h0200_2023   // 7: sw   x0, 32(x0)
  };

  localparam int RUN_CYCLES  = 3200;
  localparam int INJ_FIRST   = 400;   // 首次 flush 注入
  localparam int INJ_PERIOD  = 280;   // 注入間隔
  localparam int INJ_CYCLES  = 8;     // 預期注入次數

  // random 指令產生器 (+rand): 亂數 opcode/funct3/rd 覆蓋更多解碼/EXU/toggle 路徑
  logic rand_mode = 0;
  initial if ($test$plusargs("rand")) rand_mode = 1;
  function automatic logic [31:0] rand_insn();
    logic [6:0] op; logic [2:0] f3; logic [4:0] rd_; logic [6:0] f7;
    op  = 7'($urandom_range(0, 127));
    f3  = 3'($urandom_range(0, 7));
    rd_ = 5'($urandom_range(1, 31));
    f7  = ($urandom_range(0,1)) ? 7'h20 : 7'h00;
    if (op == 7'b0110011 || op == 7'b0010011) return {f7, 5'd0, 5'd0, f3, rd_, op}; // R/I rs=x0 (ready)
    if (op == 7'b0110011) return {7'h01, 5'd0, 5'd0, f3, rd_, op};                  // M-ext
    return {25'd0, op};                                                              // 其他 (多非法->default)
  endfunction

  int fill_cnt = 0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      for (int w = 0; w < 16; w++) begin
        if (rand_mode && ($urandom_range(0, 3) == 0))
          l2l[w*32 +: 32] <= rand_insn();       // 25% 穿插隨機指令
        else
          l2l[w*32 +: 32] <= PROG[w % 8];
      end
      l2f      <= 1'b1;
      fill_cnt <= fill_cnt + 1;
    end
  end

  // ---------------- 探針與計數 ----------------
  int prf_wr_cycles    = 0;  // (a) PRF 有寫入活動的週期數
  int prf_wr_ports_max = 0;
  int mul_wr_seen      = 0;  // MUL/DIV 寫回 (prf_wv[3], bug#9 修復後正確路由)
  int ld_wr_seen       = 0;  // LD lane 寫回 (prf_wv[8:5])
  int lane_seen [NUM_LD_PIPE];       // (b) 各 LSU lane issue 次數
  int flush_cnt        = 0;  // (c) flush 次數
  int flush_shrink_ok  = 0;  // flush 後 ROB popcount 下降次數
  int fl_rebuild_ok    = 0;  // flush 後 freelist 守恆次數
  int prf_after_flush  = 0;  // flush 後 PRF 活動恢復次數
  int fl_cnt_before = 0, fl_cnt_after = 0;
  int rob_pop_before = 0, rob_pop_after = 0;

  function automatic int rob_popcount();
    int c = 0;
    for (int i = 0; i < ROB_ENTRIES; i++)
      if (dut.u_rob.rob_array[i].valid) c++;
    return c;
  endfunction

  // flush 事件追蹤: flush 當拍記錄 before, 3 拍後記錄 after
  int flush_pending = 0;
  bit prf_seen_since_flush = 0;

  always_ff @(posedge clk) begin
    if (rst_n) begin
      // (a) PRF 寫入活動
      if (|dut.prf_wv) begin
        prf_wr_cycles <= prf_wr_cycles + 1;
        prf_seen_since_flush <= 1'b1;
        if ($countones(dut.prf_wv) > prf_wr_ports_max)
          prf_wr_ports_max <= $countones(dut.prf_wv);
      end
      if (dut.prf_wv[3])     mul_wr_seen <= mul_wr_seen + 1;
      if (|dut.prf_wv[8:5])  ld_wr_seen  <= ld_wr_seen + 1;

      // (b) LSU lane issue 活動
      for (int p = 0; p < NUM_LD_PIPE; p++)
        if (dut.mis_v[p]) lane_seen[p] <= lane_seen[p] + 1;

      // (c) flush 事件: ROB 收縮 + freelist 重建 + 活動恢復
      if (flush_pending > 0) begin
        flush_pending <= flush_pending - 1;
        if (flush_pending == 1) begin
          rob_pop_after = rob_popcount();
          fl_cnt_after  = int'(dut.u_remap.u_fl.cnt);
          // ROB: 注入 idx=head[0] => 年輕 entry 全清, popcount 必須下降
          if (rob_pop_before == 0 || rob_pop_after < rob_pop_before)
            flush_shrink_ok <= flush_shrink_ok + 1;
          // freelist 守恆: 全量重建後空閒數合法且不漏 (年輕 prd 全回收 => 不減)
          if (fl_cnt_after >= 0 && fl_cnt_after <= (INT_PRF_ENTRIES - 32) &&
              fl_cnt_after >= fl_cnt_before)
            fl_rebuild_ok <= fl_rebuild_ok + 1;
        end
      end
      if (dut.rob_flush_v && flush_pending == 0) begin
        flush_cnt      <= flush_cnt + 1;
        rob_pop_before  = rob_popcount();
        fl_cnt_before   = int'(dut.u_remap.u_fl.cnt);
        flush_pending  <= 3;
        if (prf_seen_since_flush && flush_cnt > 0)
          prf_after_flush <= prf_after_flush + 1;
        prf_seen_since_flush <= 1'b0;
      end
    end
  end

`ifdef DIRECTED_DEBUG
  int dbg_cyc = 0;
  always_ff @(posedge clk) begin
    if (rst_n && dbg_cyc < 80) begin
      dbg_cyc <= dbg_cyc + 1;
      if (dut.dv_fp != 0 || dut.fis_v != 0 || dut.mul_v || dut.mul_rv || dbg_cyc < 12)
        $display("TRACE %0d: rnov=%b dv_fp=%b fis_v=%b fis0.op=%0d fis1.op=%0d mul_v=%b rdy=%b rv=%b vec_v=%b vec_rv=%b",
          dbg_cyc, dut.rn_ov, dut.dv_fp, dut.fis_v, dut.fis_uop[0].opcode, dut.fis_uop[1].opcode,
          dut.mul_v, dut.mul_rdy, dut.mul_rv, dut.vec_v, dut.vec_rv);
    end
  end
`endif

  // ---------------- flush 強制注入 ----------------
  task automatic inject_flush();
    // 強制一拍 mispredict: rob_idx 取 thread0 目前 head (最老在飛 entry),
    // redirect 回程式起點 (TB 對所有位址皆回同一 pattern)
    force dut.bru_mispredict = 1'b1;
    force dut.bru_rob_idx    = rob_idx_t'(dut.u_rob.head[0]);
    force dut.bru_redir_pc   = 64'h0000_0000_8000_0000;
    @(negedge clk);
    release dut.bru_mispredict;
    release dut.bru_rob_idx;
    release dut.bru_redir_pc;
  endtask

  // ---------------- 主流程 ----------------
  initial begin
    tid = 2'b0;
    for (int p = 0; p < NUM_LD_PIPE; p++) lane_seen[p] = 0;
    rst_n = 0;
    #57 rst_n = 1;

    // 活動期 + 定期 flush 注入
    repeat (INJ_FIRST) @(negedge clk);
    for (int k = 0; k < INJ_CYCLES; k++) begin
      inject_flush();
      repeat (INJ_PERIOD) @(negedge clk);
    end
    repeat (RUN_CYCLES - INJ_FIRST - INJ_CYCLES * (INJ_PERIOD + 1)) @(negedge clk);

    // ---- 檢查 (a): PRF 寫入活動 ----
    if (fill_cnt == 0)      $fatal(1, "TB FAIL: directed no L2 fetch activity");
    if (prf_wr_cycles < 50) $fatal(1, "TB FAIL: directed PRF write activity too low (%0d)", prf_wr_cycles);
    if (mul_wr_seen == 0)   $fatal(1, "TB FAIL: directed no MUL/DIV writeback (prf_wv[3], exu_mul)");
    if (ld_wr_seen == 0)    $fatal(1, "TB FAIL: directed no LD-lane writeback (prf_wv[8:5])");

    // ---- 檢查 (b): LSU lane 活動 ----
    if (lane_seen[0] == 0)  $fatal(1, "TB FAIL: directed no LSU lane0 activity");

    // ---- 檢查 (c): flush 後 ROB 收縮 + freelist 回復 + 活動恢復 ----
    if (flush_cnt < INJ_CYCLES)        $fatal(1, "TB FAIL: directed flush count too low (%0d/%0d)",
                                       flush_cnt, INJ_CYCLES);
    if (flush_shrink_ok < flush_cnt)   $fatal(1, "TB FAIL: directed ROB did not shrink after flush (%0d/%0d)",
                                       flush_shrink_ok, flush_cnt);
    if (fl_rebuild_ok < flush_cnt)     $fatal(1, "TB FAIL: directed freelist not conserved after flush (%0d/%0d)",
                                       fl_rebuild_ok, flush_cnt);
    if (prf_after_flush < flush_cnt-1) $fatal(1, "TB FAIL: directed no PRF activity recovery after flush (%0d/%0d)",
                                       prf_after_flush, flush_cnt);

    $display("TB INFO: fills=%0d prf_wr_cyc=%0d max_wports=%0d vec_wb=%0d ld_wb=%0d",
      fill_cnt, prf_wr_cycles, prf_wr_ports_max, mul_wr_seen, ld_wr_seen);
    $display("TB INFO: lsu lane activity = %0d/%0d/%0d/%0d",
      lane_seen[0], lane_seen[1], lane_seen[2], lane_seen[3]);
    $display("TB INFO: flushes=%0d rob_shrink=%0d fl_rebuild=%0d prf_recover=%0d (last: rob pop %0d->%0d, fl cnt %0d->%0d)",
      flush_cnt, flush_shrink_ok, fl_rebuild_ok, prf_after_flush,
      rob_pop_before, rob_pop_after, fl_cnt_before, fl_cnt_after);
    $display("TB PASS: directed PRF/LSU/flush-freelist checks all passed");
    $finish;
  end

  // === div-by-zero 例外路徑追蹤探針 ===
  int n_mul_v=0, n_mul_exc=0, n_rob_exc=0, n_ret_exc=0, n_div=0, n_divdone=0;
  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.mul_v && dut.mul_uop.funct3 >= 4) begin
        n_div <= n_div + 1;
        if (n_div < 4) $display("[PROBE] div issued to exu_mul, funct3=%0d, rob_idx=%0d", dut.mul_uop.funct3, dut.mul_uop.rob_idx);
      end
      if (dut.u_mul.div_state == 2'd2) begin   // DIV_DONE
        n_divdone <= n_divdone + 1;
        if (n_divdone < 4) $display("[PROBE] DIV_DONE div_by_zero=%b div_divisor=%h exception=%b", dut.u_mul.div_by_zero, dut.u_mul.div_divisor, dut.u_mul.exception);
      end
      if (dut.mul_exc) begin
        n_mul_exc <= n_mul_exc + 1;
        if (n_mul_exc < 4) $display("[PROBE] EXU_MUL exception! rob_idx=%0d code=%0d", dut.mul_ri, dut.mul_excc.code);
      end
      if (dut.mul_rv && dut.mul_exc) begin
        n_rob_exc <= n_rob_exc + 1;
        if (n_rob_exc < 4) $display("[PROBE] ROB complete_exc set at rob_idx=%0d", dut.mul_ri);
      end
      if (dut.u_rob.retire_exception) begin
        n_ret_exc <= n_ret_exc + 1;
        if (n_ret_exc < 4) $display("[PROBE] ROB retire_exception! tid=%0d pc=%h", dut.u_rob.retire_tid, dut.u_rob.retire_exc_pc);
      end
    end
  end
  final begin
    $display("[PROBE SUMMARY] div_issued=%0d divdone=%0d mul_exc=%0d rob_exc=%0d retire_exc=%0d", n_div, n_divdone, n_mul_exc, n_rob_exc, n_ret_exc);
  end
endmodule : cpu_directed_tb
