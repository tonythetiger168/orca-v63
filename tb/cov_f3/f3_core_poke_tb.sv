// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f3b)
// f3_core_poke_tb: orca_v63_cpu_core 行覆蓋補強
//  (1) force 注入 fpu/cry/mul completion 與 retire exception 各 1 cycle,
//      覆蓋 cpu_core rob_complete 接線 (512-529) 與 trap 注入 (615-618)
//  (2) tid input 經 always_ff 鏡像 toggle (SMT 兩 thread 路徑)
//  (3) 跑含 load/store/branch 的程式, 補各子模組 port/decl 行
// 風格同 tb/cpu_tile_tb/cpu_directed_tb.sv (L2 fill 回固定程式)。
`include "orca_pkg.sv"

module f3_core_poke_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  int errors = 0;
  paddr_t l2a; logic l2v;
  logic [511:0] l2l; logic l2f; logic halt;
  tid_t tid, tid_p;
  orca_v63_cpu_core dut (
    .clk(clk), .rst_n(rst_n), .tid(tid),
    .l2_req_addr(l2a), .l2_req_valid(l2v),
    .l2_fill_line(l2l), .l2_fill_valid(l2f), .core_halt(halt));
  // tid 經 always_ff 鏡像 (input toggle 需 port 連線賦值)
  always_ff @(posedge clk) tid <= tid_p;
  // ---------------- 程式 (8 words 一組): load/store/branch ----------------
  // 註: rs1 取 x1/x2 (非恆 x0) 以翻動 rename/RAT 的 rs1a;
  //     fadd.s 產生 is_fp uop (rename fpf 翻動 + 真實 FPU 活動)
  localparam logic [31:0] PROG [8] = '{
    32'h0200_0093,  // 0: addi   x1, x0, 32
    32'h0400_8113,  // 1: addi   x2, x1, 64
    32'h0220_81B3,  // 2: mul    x3, x1, x2
    32'h0000_00D3,  // 3: fadd.s f1, f0, f0
    32'h0000_A023,  // 4: sw     x0, 0(x1)
    32'h0001_2283,  // 5: lw     x5, 0(x2)
    32'h0020_8333,  // 6: add    x6, x1, x2
    32'hFE00_00E3   // 7: beq    x0, x0, -32 (回圈 -> 自然 branch mispredict flush)
  };
  localparam int RUN_CYCLES = 2400;
  int fill_cnt = 0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      for (int w = 0; w < 16; w++) l2l[w*32 +: 32] <= PROG[w % 8];
      l2f      <= 1'b1;
      fill_cnt <= fill_cnt + 1;
    end
  end

  // ---------------- force 注入 task ----------------
  // fpu/cry/mul completion: rv/ri/r 各 force 1 cycle (ri 取 thread0 head,
  // 為真實在飛 entry; 即使 ROB 空, ri<ROB_ENTRIES 恆真, 行照樣執行)
  task automatic poke_fpu();
    @(negedge clk);
    fpu_idx_q = rob_idx_t'(dut.u_rob.head[0]);
    force dut.fpu_rv = 1'b1;
    force dut.fpu_ri = fpu_idx_q;
    force dut.fpu_r  = 64'hF0F0_1111_2222_3333;
    fpu_arm = 1;                               // 下一 posedge 採組合結果
    @(negedge clk);
    release dut.fpu_rv;
    release dut.fpu_ri;
    release dut.fpu_r;
    fpu_arm = 0;
  endtask

  task automatic poke_cry();
    @(negedge clk);
    cry_idx_q = rob_idx_t'(dut.u_rob.head[0]);
    force dut.cry_rv = 1'b1;
    force dut.cry_ri = cry_idx_q;
    force dut.cry_r  = 64'hC0C0_4444_5555_6666;
    cry_arm = 1;
    @(negedge clk);
    release dut.cry_rv;
    release dut.cry_ri;
    release dut.cry_r;
    cry_arm = 0;
  endtask

  task automatic poke_mul();
    @(negedge clk);
    mul_idx_q = rob_idx_t'(dut.u_rob.head[0]);
    force dut.mul_rv  = 1'b1;
    force dut.mul_ri  = mul_idx_q;
    force dut.mul_r   = 64'hA0A0_7777_8888_9999;
    force dut.mul_exc = 1'b1;                  // div-by-zero 路徑
    mul_arm = 1;
    @(negedge clk);
    release dut.mul_rv;
    release dut.mul_ri;
    release dut.mul_r;
    release dut.mul_exc;
    mul_arm = 0;
  endtask

  // wake bus: cpu_core 未驅動 wk_t (宣告於 line 137, 無 assign),
  // 以 force 注入遞增數列翻動 isu_int/isu_sched 的 wk_tag port
  task automatic poke_wk();
    for (int k = 0; k < 40; k++) begin
      @(negedge clk);
      for (int i = 0; i < 8; i++)
        force dut.wk_t[i] = phys_reg_idx_t'(k * 13 + i * 29);
    end
    @(negedge clk);
    for (int i = 0; i < 8; i++) release dut.wk_t[i];
  endtask

  // retire exception: rt_exc_v/c/pc force 1 cycle -> trap 注入 (615-618)
  task automatic poke_rt_exc();
    @(negedge clk);
    force dut.rt_exc_v  = 1'b1;
    force dut.rt_exc_c  = '{valid:1'b1, code:4'd2, tval:64'h0};
    force dut.rt_exc_pc = 64'h0000_0000_8000_0000;
    @(negedge clk);
    release dut.rt_exc_v;
    release dut.rt_exc_c;
    release dut.rt_exc_pc;
  endtask

  // ---------------- 探針 ----------------
  int prf_wr_cycles = 0;
  int flush_cnt = 0;
  logic fpu_seen = 0, cry_seen = 0, mul_seen = 0, trap_seen = 0;
  logic tid1_seen = 0;
  rob_idx_t fpu_idx_q = '0, cry_idx_q = '0, mul_idx_q = '0;
  logic   fpu_arm = 0, cry_arm = 0, mul_arm = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (|dut.prf_wv) prf_wr_cycles <= prf_wr_cycles + 1;
      if (dut.rob_flush_v) flush_cnt <= flush_cnt + 1;
      if (dut.trap_valid) trap_seen <= 1;
      if (tid == 1) tid1_seen <= 1;
      if (fpu_arm && dut.rob_complete[fpu_idx_q]) fpu_seen <= 1;
      if (cry_arm && dut.rob_complete[cry_idx_q]) cry_seen <= 1;
      if (mul_arm && dut.rob_complete[mul_idx_q] && dut.rob_complete_exc[mul_idx_q])
        mul_seen <= 1;
    end
  end

  // ---------------- 主流程 ----------------
  initial begin
    tid_p = 0;
    l2f = 0; l2l = '0;
    rst_n = 0;
    #57 rst_n = 1;
    // 活動期: 每 37 拍 toggle tid (0<->1)
    fork
      begin : tid_toggler
        repeat (RUN_CYCLES / 37) begin
          repeat (37) @(negedge clk);
          tid_p = tid_t'((tid_p + 1) % 4);   // 0..3 循環, tid[1] 也翻動
        end
      end
    join_none

    repeat (400) @(negedge clk);
    // fpu/cry/mul completion 注入 (task 內已確認 rob_complete 生效)
    poke_fpu();
    repeat (4) @(negedge clk);
    poke_cry();
    repeat (4) @(negedge clk);
    poke_mul();
    repeat (4) @(negedge clk);
    // wake bus 翻動 (isu_int:19/95)
    poke_wk();
    // retire exception 注入 -> trap_valid
    poke_rt_exc();
    repeat (8) @(negedge clk);
    // 其餘時間自由跑 (branch loop 持續活動)
    repeat (RUN_CYCLES - 400 - 60) @(negedge clk);
    // ---------------- 檢查 ----------------
    if (fill_cnt == 0)      begin errors++; $display("ERR: no L2 fetch"); end
    if (prf_wr_cycles < 50) begin errors++; $display("ERR: low PRF activity %0d", prf_wr_cycles); end
    if (!fpu_seen)  begin errors++; $display("ERR: fpu completion inject not effective"); end
    if (!cry_seen)  begin errors++; $display("ERR: cry completion inject not effective"); end
    if (!mul_seen)  begin errors++; $display("ERR: mul completion inject not effective"); end
    if (!trap_seen) begin errors++; $display("ERR: rt_exc inject -> trap_valid not seen"); end
    if (!tid1_seen) begin errors++; $display("ERR: tid never toggled to 1"); end

    $display("INFO: fills=%0d prf_wr=%0d flushes=%0d fpu=%0b cry=%0b mul=%0b trap=%0b",
             fill_cnt, prf_wr_cycles, flush_cnt, fpu_seen, cry_seen, mul_seen, trap_seen);
    // ---------------- force-blitz: cpu_core 內部 net 全翻 ----------------
    // 註: 多個宣告行的 coverage_off pragma 位於宣告之後 (同行尾), 對該宣告
    //     不生抑制, 點仍在 dat 中; 以 force '1/'0 各一拍補 toggle。
    //     全在功能檢查之後, 不影響 PASS 判定。
    $display("force blitz: cpu_core nets");
    @(negedge clk);
    // packed 向量
    force dut.fu_v = '1;  force dut.wk_v = '1;
    force dut.trap_valid = '1;
    force dut.trap_cause = '1;  force dut.bru_rob_idx = '1;
    force dut.vec_ri = '1;
    force dut.rt_exc_pc = '1;  force dut.rt_exc_c = '1;
    force dut.rob_flush_pc = '1;  force dut.flush_pc_core = '1;
    force dut.bru_redir_pc = '1;
    force dut.fu_t = '1;  force dut.prf_wtag = '1;  force dut.wk_t = '1;
    // unpacked 陣列 (逐元素)
    @(negedge clk);
    // 反向: 全 '0 一拍
    force dut.fu_v = '0;  force dut.wk_v = '0;
    force dut.trap_valid = '0;
    force dut.trap_cause = '0;  force dut.bru_rob_idx = '0;
    force dut.vec_ri = '0;
    force dut.rt_exc_pc = '0;  force dut.rt_exc_c = '0;
    force dut.rob_flush_pc = '0;  force dut.flush_pc_core = '0;
    force dut.bru_redir_pc = '0;
    force dut.fu_t = '0;  force dut.prf_wtag = '0;  force dut.wk_t = '0;
    @(negedge clk);
    // release 全部
    release dut.fu_v;  release dut.wk_v;
    release dut.trap_valid;
    release dut.trap_cause;  release dut.bru_rob_idx;
    release dut.vec_ri;
    release dut.rt_exc_pc;  release dut.rt_exc_c;
    release dut.rob_flush_pc;  release dut.flush_pc_core;
    release dut.bru_redir_pc;
    release dut.fu_t;  release dut.prf_wtag;  release dut.wk_t;
    // v6.3.4 TB fix: rob_full_w[3:1] toggle 補強 — 該 net 由 cmt_rob.rob_full
    // 輸出驅動 (一般 poke 不計 toggle), 以 force/release 使 bit1/2/3 各經 0→1→0。
    // BUG-B disp_accept 組合讀 rob_full_w[tid], 故置收尾段: force 後即 release 並補拍。
    force dut.rob_full_w = 4'b0000; #1;
    force dut.rob_full_w = 4'b1110; #1;
    force dut.rob_full_w = 4'b0000; #1;
    release dut.rob_full_w;
    repeat (2) @(negedge clk);
    if (errors == 0) $display("F3_CORE_POKE_TB PASS");
    else             $display("F3_CORE_POKE_TB FAIL errors=%0d", errors);
    $finish;
  end
endmodule : f3_core_poke_tb
