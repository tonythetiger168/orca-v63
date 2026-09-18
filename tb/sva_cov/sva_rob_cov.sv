//=============================================================================
// ORCA v6.3.3.2 SVA 覆蓋率量測 checker - ROB (對應 tb/sva/sva_rob.sv 22 顆)
// 說明: Verilator 5.006 不支援 ## 序列, 以程序式 FSM/計數器量測:
//   每 property 計 attempts (前提非虛空觸發) 與 fails (後件違反)
// Port 與 sva_rob 相同 (供 TB 以階層引用銜接 DUT 內部訊號)
// 語意銜接 (對照表, 詳 sva_cov_report.txt):
//   [M1] head/tail 為 local partition 指標 (0..ROB_PER_THREAD-1);
//        全域 index = t*ROB_PER_THREAD + local
//   [M2] rob_valid/rob_complete/rob_exception 由 rob_array[i] 欄位推導
//   [M3] R8/R9 之 ROB slot 以「slot0 = thread_base(tid)+tail[tid]」計算
//        (原 SVA 誤以 uop_id 為 ROB index)
//   [M4] R13/R14 之 flush 限定 exception flush (v6.3.3 R19 已明定
//        mispredict flush 保留 head/舊 entry, 與 R13/R14 字面互斥)
//   [M5] R16/R17 以 streak 實作 ##[1:N] 視窗 (每空/滿 cycle 計一次 attempt)
//   [M6] R11/R12 只計「提交成功」的 retire: flush 同拍 DUT 優先 flush,
//        rob_array_next/head_next 不提交, 該 retire 下拍重試 (entry 仍在);
//        故前提加 !flush_valid (v6.3.3.2 實測: flush 拍 retire_valid 仍組合
//        輸出但被捨棄, 屬前提不成立而非後件違反)
//=============================================================================
`include "orca_pkg.sv"

module sva_rob_cov
  import orca_pkg::*; (
  input logic clk,
  input logic rst_n,

  input rob_entry_t [ROB_ENTRIES-1:0] rob_array,
  input logic       [ROB_ENTRIES-1:0] rob_valid,
  input logic       [ROB_ENTRIES-1:0] rob_complete,
  input logic       [ROB_ENTRIES-1:0] rob_exception,
  input rob_idx_t   [SMT_THREADS-1:0] head,
  input rob_idx_t   [SMT_THREADS-1:0] tail,
  input logic       [SMT_THREADS-1:0] rob_full,
  input logic       [SMT_THREADS-1:0] rob_empty,

  input logic [DISPATCH_WIDTH-1:0] disp_valid,
  input uop_t [DISPATCH_WIDTH-1:0] disp_uop,

  input logic [RETIRE_WIDTH-1:0] retire_valid,
  input rob_entry_t [RETIRE_WIDTH-1:0] retire_entry,

  input logic flush_valid,
  input tid_t flush_tid,

  input logic     exception_detected,
  input rob_idx_t exception_rob_idx,
  input tid_t     exception_tid,

  input logic        br_mispredict,
  input rob_idx_t    br_mispredict_rob_idx,
  input logic [15:0] fl_free_cnt,
  input logic        fl_empty
);

  localparam int ROB_PER_THREAD = ROB_ENTRIES / SMT_THREADS;
  localparam int NP = 22;  // R1..R21(含 R21a/R21b) + R16 + R17

  // property 名稱表
  localparam string PNAME [NP] = '{
    "R1_head_in_range",        "R2_tail_in_range",       "R3_head_not_overtake",
    "R4_valid_in_range",       "R5_complete_impl_valid", "R6_exc_impl_complete",
    "R7_no_dispatch_full",     "R8_dispatch_valid",      "R9_dispatch_not_complete",
    "R10_retire_safe",         "R11_retire_adv_head",    "R12_retire_invalidates",
    "R13_flush_invalidate",    "R14_flush_reset_head",   "R15_exception_oldest",
    "R18_exc_flush_empties",   "R19_mispredict_rewind",  "R20_freelist_flush_recover",
    "R21a_freelist_bounded",   "R21b_no_disp_fl_empty",  "R16_empty_accept_dispatch",
    "R17_full_eventually_retire" };

  int att  [NP];
  int fail [NP];
  int cyc = 0;

  // 前級取樣 ($past 等價)
  rob_idx_t head_q [SMT_THREADS];
  logic [15:0] fl_cnt_q;
  // R8/R9 一拍管線
  logic        d8_v;  rob_idx_t d8_idx;
  // R11 一拍管線 (per thread)
  logic [SMT_THREADS-1:0] d11_v;
  rob_idx_t d11_head [SMT_THREADS];
  // R12 一拍管線
  logic        d12_v; rob_idx_t d12_idx;
  // R13/R14/R18 一拍管線
  logic        d13_v, d18_v;  tid_t d13_tid;
  // R19 一拍管線
  logic        d19_v;  tid_t d19_t;  rob_idx_t d19_newtail;  rob_idx_t d19_head;
  // R20 一拍管線
  logic        d20_v;  logic [15:0] d20_cnt;
  // R16/R17 streak
  int empty_streak [SMT_THREADS];
  int full_streak  [SMT_THREADS];

  function automatic rob_idx_t abs_idx(input tid_t t, input rob_idx_t local_p);
    return rob_idx_t'(int'(t) * ROB_PER_THREAD + (int'(local_p) % ROB_PER_THREAD));
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NP; i++) begin att[i] <= 0; fail[i] <= 0; end
      cyc <= 0;
      d8_v <= 0; d11_v <= '0; d12_v <= 0; d13_v <= 0; d18_v <= 0;
      d19_v <= 0; d20_v <= 0;
      for (int t = 0; t < SMT_THREADS; t++) begin
        head_q[t] <= '0; empty_streak[t] <= 0; full_streak[t] <= 0;
      end
      fl_cnt_q <= '0;
    end else begin
      cyc <= cyc + 1;
      for (int t = 0; t < SMT_THREADS; t++) head_q[t] <= head[t];
      fl_cnt_q <= fl_free_cnt;

      // ---- R1/R2: head/tail 在分區範圍內 (local: < ROB_PER_THREAD) [M1] ----
      for (int t = 0; t < SMT_THREADS; t++) begin
        att[0]++; if (int'(head[t]) >= ROB_PER_THREAD) fail[0]++;
        att[1]++; if (int'(tail[t]) >= ROB_PER_THREAD) fail[1]++;
      end

      // ---- R3: head 不得超越 tail (環形不變式) ----
      for (int t = 0; t < SMT_THREADS; t++) begin
        if (!flush_valid) begin
          att[2]++;
          if (!(((head[t] <= tail[t]) && (int'(tail[t]) - int'(head[t]) <= ROB_PER_THREAD)) ||
                ((head[t] >  tail[t]) && (ROB_PER_THREAD - int'(head[t]) + int'(tail[t]) <= ROB_PER_THREAD))))
            fail[2]++;
        end
      end

      // ---- R4: valid entry 必在 head~tail 之間 [M1][M2] ----
      begin
        automatic bit any_v = 1'b0, bad = 1'b0;
        for (int i = 0; i < ROB_ENTRIES; i++) begin
          if (rob_valid[i]) begin
            automatic int t  = i / ROB_PER_THREAD;
            automatic int li = i % ROB_PER_THREAD;
            automatic bit inwin;
            any_v = 1'b1;
            if (head[t] <= tail[t])
              inwin = (li >= int'(head[t])) && (li < int'(tail[t]));
            else
              inwin = (li >= int'(head[t])) || (li < int'(tail[t]));
            if (!inwin) bad = 1'b1;
          end
        end
        if (any_v) begin att[3]++; if (bad) fail[3]++; end
      end

      // ---- R5: complete => valid ----
      if (rob_complete != '0) begin
        att[4]++;
        if ((rob_complete & ~rob_valid) != '0) fail[4]++;
      end
      // ---- R6: exception => complete ----
      if (rob_exception != '0) begin
        att[5]++; if ((rob_exception & ~rob_complete) != '0) fail[5]++;
      end

      // ---- R7: full 時不得 dispatch 至該 thread ----
      for (int t = 0; t < SMT_THREADS; t++) begin
        if (rob_full[t]) begin
          att[6]++;
          if (disp_valid[0] && int'(disp_uop[0].tid) == t) fail[6]++;
        end
      end

      // ---- R8/R9: slot0 dispatch 的 entry 下拍 valid=1 / complete=0 [M3] ----
      if (d8_v) begin
        if (!rob_valid[d8_idx])   fail[7]++;
        if (rob_complete[d8_idx]) fail[8]++;
      end
      if (disp_valid[0]) begin
        automatic tid_t t = disp_uop[0].tid;
        att[7]++; att[8]++;
        d8_v   <= 1'b1;
        d8_idx <= abs_idx(t, tail[t]);
      end else d8_v <= 1'b0;

      // ---- R10: retire 只發生在 valid+complete+非例外 entry ----
      if (retire_valid[0]) begin
        automatic tid_t t = retire_entry[0].uop.tid;
        automatic rob_idx_t ah = abs_idx(t, head[t]);
        att[9]++;
        if (!(rob_valid[ah] && rob_complete[ah] && !rob_exception[ah])) fail[9]++;
      end

      // ---- R11: retire 後 head 前進 (或 flush) ----
      for (int t = 0; t < SMT_THREADS; t++) begin
        if (d11_v[t]) begin
          if (!(head[t] != d11_head[t] || flush_valid)) fail[10]++;
        end
        d11_v[t] <= 1'b0;
        if (retire_valid[0] && !flush_valid &&  // [M6] flush 同拍 retire 被捨棄
            int'(retire_entry[0].uop.tid) == t) begin
          att[10]++;
          d11_v[t]    <= 1'b1;
          d11_head[t] <= head[t];
        end
      end

      // ---- R12: retired entry 下拍失效 [M1] ----
      if (d12_v) begin
        if (rob_valid[d12_idx]) fail[11]++;
      end
      if (retire_valid[0] && !flush_valid) begin  // [M6]
        automatic tid_t t = retire_entry[0].uop.tid;
        att[11]++;
        d12_v   <= 1'b1;
        d12_idx <= abs_idx(t, head[t]);
      end else d12_v <= 1'b0;

      // ---- R13/R14: exception flush 清分區 / head=tail [M4] ----
      if (d13_v) begin
        if (rob_valid[int'(d13_tid) * ROB_PER_THREAD +: ROB_PER_THREAD] != '0) fail[12]++;
        if (head[d13_tid] != tail[d13_tid]) fail[13]++;
      end
      if (flush_valid && exception_detected) begin
        att[12]++; att[13]++;
        d13_v <= 1'b1; d13_tid <= flush_tid;
      end else d13_v <= 1'b0;

      // ---- R15: 例外必在 retire 頭端 ----
      if (exception_detected) begin
        att[14]++;
        if (exception_rob_idx != abs_idx(exception_tid, head[exception_tid])) fail[14]++;
      end

      // ---- R18: 例外 flush 後該 thread ROB 全空 ----
      if (d18_v) begin
        if (!rob_empty[d13_tid]) fail[15]++;
      end
      if (flush_valid && exception_detected) begin
        att[15]++;
        d18_v <= 1'b1;
      end else d18_v <= 1'b0;

      // ---- R19: mispredict 精確回捲 tail=branch+1, head 不變 ----
      if (d19_v) begin
        if (tail[d19_t] != d19_newtail || head[d19_t] != d19_head) fail[16]++;
      end
      if (flush_valid && br_mispredict && !exception_detected) begin
        automatic int t  = int'(br_mispredict_rob_idx) / ROB_PER_THREAD;
        automatic int bl = int'(br_mispredict_rob_idx) % ROB_PER_THREAD;
        att[16]++;
        d19_v       <= 1'b1;
        d19_t       <= tid_t'(t);
        d19_newtail <= rob_idx_t'((bl + 1) % ROB_PER_THREAD);
        d19_head    <= head[t];
      end else d19_v <= 1'b0;

      // ---- R20: flush 後 freelist 空閒數不降且不超池 ----
      if (d20_v) begin
        if (!(fl_free_cnt >= d20_cnt && int'(fl_free_cnt) <= (INT_PRF_ENTRIES - 32)))
          fail[17]++;
      end
      if (flush_valid) begin
        att[17]++;
        d20_v   <= 1'b1;
        d20_cnt <= fl_free_cnt;
      end else d20_v <= 1'b0;

      // ---- R21a: freelist 空閒數守恆上界 ----
      att[18]++;
      if (int'(fl_free_cnt) > (INT_PRF_ENTRIES - 32)) fail[18]++;
      // ---- R21b: freelist 空時不得 dispatch ----
      if (fl_empty) begin
        att[19]++;
        if (|disp_valid) fail[19]++;
      end

      // ---- R16: 空 ROB 於 10 拍內接受 dispatch [M5] ----
      for (int t = 0; t < SMT_THREADS; t++) begin
        if (rob_empty[t]) begin
          att[20]++;
          empty_streak[t] <= empty_streak[t] + 1;
          if (empty_streak[t] >= 10) fail[20]++;
        end else empty_streak[t] <= 0;
      end
      // ---- R17: 滿 ROB 於 100 拍內退休 [M5] ----
      for (int t = 0; t < SMT_THREADS; t++) begin
        if (rob_full[t]) begin
          att[21]++;
          full_streak[t] <= full_streak[t] + 1;
          if (full_streak[t] >= 100) fail[21]++;
        end else full_streak[t] <= 0;
      end
    end
  end

  final begin
    int nonvac, tot_fail;
    nonvac = 0; tot_fail = 0;
    $display("==== sva_rob_cov 總表 ====");
    for (int i = 0; i < NP; i++) begin
      if (att[i] >= 1) nonvac++;
      tot_fail += fail[i];
      $display("SVACOV|ROB|%s|attempts=%0d|fails=%0d", PNAME[i], att[i], fail[i]);
    end
    $display("SVA_COV: sva_rob %0d/%0d nonvacuous, %0d fail", nonvac, NP, tot_fail);
  end

endmodule : sva_rob_cov
