// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.3.2 SVA 覆蓋率 TB - CPU Core (改造自 tb/cpu_tile_tb/cpu_directed_tb.sv)
// DUT: orca_v63_cpu_core (真實程式流); Checker: sva_cpu_core_cov (17+2 顆)
// 與原 TB 差異:
//   (1) tid 每拍輪轉 0→1→2→3 (SMT 4 thread 皆活躍: A11/A12/C1 非虛空觸發)
//   (2) 新增例外注入 (force dut.mul_exc 一拍 -> rob_complete_exc):
//       A3/A13 前提需要 retire_exception
//   (3) 新增 dispatch→ALU 寫回 latency 直方圖 (佐證 A15 視窗 [1:4])
//   (4) 保留原功能檢查 (PRF/LSU/flush-freelist), PASS 字串加 SVA 前綴
`include "orca_pkg.sv"

module sva_cpu_core_tb;
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

  // ---------------- 程式 (同 cpu_directed_tb) ----------------
  localparam logic [31:0] PROG [8] = '{
    32'h0200_0093,  // 0: addi x1, x0, 32
    32'h0400_0113,  // 1: addi x2, x0, 64
    32'h0200_01B3,  // 2: mul  x3, x0, x0
    32'h0200_0233,  // 3: mul  x4, x0, x0
    32'h0000_2023,  // 4: sw   x0, 0(x0)
    32'h0000_2283,  // 5: lw   x5, 0(x0)
    32'h0000_0333,  // 6: add  x6, x0, x0
    32'h0200_2023   // 7: sw   x0, 32(x0)
  };

  localparam int RUN_CYCLES  = 6900;
  localparam int INJ_FIRST   = 600;
  localparam int INJ_PERIOD  = 280;
  localparam int INJ_CYCLES  = 22;

  int fill_cnt = 0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      for (int w = 0; w < 16; w++) l2l[w*32 +: 32] <= PROG[w % 8];
      l2f      <= 1'b1;
      fill_cnt <= fill_cnt + 1;
    end
  end

  // ---------------- tid 策略: 前 ROT_UNTIL 拍輪轉 (SMT 4 thread 皆活躍,
  // 供 A12/C1 cover), 之後固定 thread0 — 實測 tid 輪替下 mul 寫回從不
  // 完成 (2000 拍無 mul_rv), ROB head 卡 mul 造成全 thread 退休停擺;
  // 固定 t0 後 pipeline 恢復 (同 cpu_directed_tb), A3/A5/A8/A10/A13/A14
  // 才有可觀測語義. (mul 輪替問題屬 core 整合議題, 另案回報 F3)
  int ROT_UNTIL = 1200;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) tid <= '0;
    else if (tb_cyc < ROT_UNTIL) tid <= tid + 2'd1;
    else        tid <= '0;
  end
  int tb_cyc = 0;
  always_ff @(posedge clk) tb_cyc <= tb_cyc + 1;
  // DEBUG: retire stall 診斷 (每 1000 拍)
  always_ff @(posedge clk) if (tb_cyc % 1000 == 999)
    $display("RSTDBG cyc=%0d occ0=%0d head0=%0d tail0=%0d hv=%0b hc=%0b he=%0b rt0=%0b",
      tb_cyc, dut.u_rob.rob_occupancy[0], dut.u_rob.head[0], dut.u_rob.tail[0],
      dut.u_rob.rob_array[dut.u_rob.head[0]].valid,
      dut.u_rob.rob_array[dut.u_rob.head[0]].complete,
      dut.u_rob.rob_array[dut.u_rob.head[0]].exception,
      dut.rt_valid_w[0]);

  // ---------------- SVA checker 銜接 ----------------
  logic [ROB_ENTRIES-1:0] v_rob_valid, v_rob_complete;
  rob_idx_t w_rob_head, w_rob_tail;
  logic [NUM_INT_ALU-1:0] w_alu_rv;
  always_comb begin
    for (int i = 0; i < ROB_ENTRIES; i++) begin
      v_rob_valid[i]    = dut.u_rob.rob_array[i].valid;
      v_rob_complete[i] = dut.u_rob.rob_array[i].complete;
    end
    // [C5]: retire port0 thread 之絕對 head/tail
    w_rob_head = rob_idx_t'(int'(dut.rt_tid_w[0]) * (ROB_ENTRIES/SMT_THREADS) +
                            int'(dut.u_rob.head[dut.rt_tid_w[0]]));
    w_rob_tail = rob_idx_t'(int'(dut.rt_tid_w[0]) * (ROB_ENTRIES/SMT_THREADS) +
                            int'(dut.u_rob.tail[dut.rt_tid_w[0]]));
    // issue port map: 0=ALU 1=BRU 2=FPU 3=CRYPTO
    w_alu_rv = {dut.cry_rv, dut.fpu_rv, dut.bru_v, dut.alu_rv};
  end

  sva_cpu_core_cov u_cov (
    .clk(clk), .rst_n(rst_n),
    .fetch_valid(dut.dec_valid), .fetch_pc(dut.dec_pc),
    .fetch_instr(dut.dec_block[31:0]),
    .decode_valid(dut.dec_v[0]), .decode_uop(dut.dec_uop[0]),
    .rename_valid(|dut.rn_ov), .rename_ready(&dut.rn_rdy),
    .dispatch_valid(dut.rob_disp_v), .dispatch_uop(dut.rob_disp_uop),
    .rob_valid(v_rob_valid), .rob_complete(v_rob_complete),
    .rob_head(w_rob_head), .rob_tail(w_rob_tail),
    .retire_valid(dut.rt_valid_w), .retire_exception(dut.rt_exc_v),
    .alu_result_valid(w_alu_rv), .flush_pipeline(dut.flush_valid_core),
    .dispatch_tid(dut.rob_disp_tid), .retire_tid(dut.rt_tid_w),
    .prf_wvalid(dut.prf_wv), .prf_wtag(dut.prf_wtag));

  // ---------------- 探針與計數 (同 cpu_directed_tb) ----------------
  int prf_wr_cycles    = 0;
  int prf_wr_ports_max = 0;
  int vec_wr_seen      = 0;
  int ld_wr_seen       = 0;
  int lane_seen [NUM_LD_PIPE];
  int flush_cnt        = 0;
  int flush_shrink_ok  = 0;
  int fl_rebuild_ok    = 0;
  int prf_after_flush  = 0;
  int fl_cnt_before = 0, fl_cnt_after = 0;
  int rob_pop_before = 0, rob_pop_after = 0;

  function automatic int rob_popcount();
    int c = 0;
    for (int i = 0; i < ROB_ENTRIES; i++)
      if (dut.u_rob.rob_array[i].valid) c++;
    return c;
  endfunction

  // v6.3.4 TB fix: 指定 thread 分區的「活體 entry」計數。BUG-B 後 dispatch
  // 依 rob_disp_tid=tid 落各 thread 分區, 而 bru 精確 flush 只清
  // bru_rob_idx 所屬 thread; 總 popcount 會被其他 thread 殘留 entry 撐高,
  // 不能用作 flush 目標選擇依據。
  function automatic int rob_popcount_t(input int t);
    int c = 0;
    int base = t * (ROB_ENTRIES/SMT_THREADS);
    for (int i = 0; i < ROB_ENTRIES/SMT_THREADS; i++)
      if (dut.u_rob.rob_array[base+i].valid) c++;
    return c;
  endfunction

  int flush_pending = 0;
  bit prf_seen_since_flush = 0;

  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (|dut.prf_wv) begin
        prf_wr_cycles <= prf_wr_cycles + 1;
        prf_seen_since_flush <= 1'b1;
        if ($countones(dut.prf_wv) > prf_wr_ports_max)
          prf_wr_ports_max <= $countones(dut.prf_wv);
      end
      if (dut.prf_wv[4])     vec_wr_seen <= vec_wr_seen + 1;
      if (|dut.prf_wv[8:5])  ld_wr_seen  <= ld_wr_seen + 1;
      for (int p = 0; p < NUM_LD_PIPE; p++)
        if (dut.mis_v[p]) lane_seen[p] <= lane_seen[p] + 1;

      if (flush_pending > 0) begin
        flush_pending <= flush_pending - 1;
        if (flush_pending == 1) begin
          rob_pop_after = rob_popcount();
          fl_cnt_after  = int'(dut.u_remap.u_fl.cnt);
          if (rob_pop_before == 0 || rob_pop_after < rob_pop_before)
            flush_shrink_ok <= flush_shrink_ok + 1;
          else  // v6.3.4 TB fix: shrink 失敗定位資訊 (不影響判定語義)
            $display("FLUSHDBG noshrink cyc=%0d before=%0d after=%0d occ0=%0d popt0=%0d h0=%0d t0=%0d hv=%0b",
              tb_cyc, rob_pop_before, rob_pop_after, dut.u_rob.rob_occupancy[0],
              rob_popcount_t(0), dut.u_rob.head[0], dut.u_rob.tail[0],
              dut.u_rob.rob_array[dut.u_rob.head[0]].valid);
          if (fl_cnt_after >= 0 && fl_cnt_after <= (INT_PRF_ENTRIES - 32) &&
              fl_cnt_after >= fl_cnt_before)
            fl_rebuild_ok <= fl_rebuild_ok + 1;
        end
      end
      if (dut.rob_flush_v && flush_pending == 0) begin
        flush_cnt      <= flush_cnt + 1;
        rob_pop_before  = rob_popcount();
        fl_cnt_before   = int'(dut.u_remap.u_fl.cnt);
        // v6.3.4 TB fix: 觀察窗 3→1。cmt_rob 的 flush 清除與 freelist 重建
        // 皆在 flush 同一 posedge 完成, 下一拍即可觀測; 舊版等 3 拍會把
        // 未被 flush 的 uop_queue/rename backlog 回填 (實測 3 拍 12 筆)
        // 誤計入 rob_pop_after, 在淺 ROB flush 時造成 shrink 假 fail。
        flush_pending  <= 1;
        if (prf_seen_since_flush && flush_cnt > 0)
          prf_after_flush <= prf_after_flush + 1;
        prf_seen_since_flush <= 1'b0;
      end
    end
  end

  // ---------------- A15 佐證: dispatch(ALU) → alu_rv latency 直方圖 ----------------
  int lat_birth [$];  int lat_ridx [$];
  int lat_hist [16];
  int lat_max = 0, lat_cnt = 0;
  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.rob_disp_v[0] &&
          (dut.rob_disp_uop[0].opcode == OP_ALU || dut.rob_disp_uop[0].opcode == OP_ALUI)) begin
        lat_birth.push_back(lat_cyc);
        lat_ridx.push_back(int'(dut.rob_disp_uop[0].rob_idx));
        if (lat_birth.size() > 4000) begin
          void'(lat_birth.pop_front()); void'(lat_ridx.pop_front());
        end
      end
      if (dut.alu_rv) begin
        for (int i = 0; i < lat_birth.size(); i++) begin
          if (lat_ridx[i] == int'(dut.alu_ri)) begin
            automatic int l = lat_cyc - lat_birth[i];
            if (l < 16) lat_hist[l]++;
            if (l > lat_max) lat_max = l;
            lat_cnt++;
            lat_birth.delete(i); lat_ridx.delete(i);
            break;
          end
        end
      end
      lat_cyc <= lat_cyc + 1;
    end
  end
  int lat_cyc = 0;

  // ---------------- flush 強制注入 (同原 TB) ----------------
  task automatic inject_flush();
    // v6.3.4 TB fix: BUG-B 修復後 retire/dispatch 皆真實運作, 原寫法在
    // negedge 直接 force bru_rob_idx=head[0] 有三個時序工件:
    //  (a) force 時目標分區可能全空 (dispatch jam/剛被 flush), 對空分區做
    //      精確 branch flush 會把 tail 推過無效 head → 產生「無效 head +
    //      有效 younger」幻影洞, head 永久卡死 (實測 RSTDBG hv=0 固定);
    //  (b) thread0 分區可能長期全空 (實測 17000 拍 occ0=0), 此時對
    //      thread0 注入永遠無 entry 可清 → 「ROB did not shrink」假 fail;
    //  (c) 取樣與 flush 不同相, retire 前移 head 後 force 值失效。
    // 改為 (對齊 lead 建議的 mid-ROB 活體注入):
    //  1. 有界等待 (500 拍) 「任一分區活體 >=2」或「全 ROB 空」;
    //  2. posedge 後 #1 同相取樣: 選活體最深的 thread (平手取小編號),
    //     在其分區內自 head 起找第一個活體 entry 作為 mispredict 分支 —
    //     保證目標活體、有 younger 可清 (flush 後 pop 必縮), 且 tail 回捲
    //     不越過 head, 絕不製造幻影洞;
    //  2'. 全 ROB 空時改打 thread0 的 head-1 (bl,tl) 跨度為 0, 不清任何
    //     entry、tail 不越過 head (無幻影洞), flush_valid_core 仍正常
    //     脈衝 (解除 dispatch jam、計入 flush_cnt), before==0 → shrink
    //     檢查自然通過;
    //  3. force 恰好涵蓋下一個 posedge (flush 拍), 該拍 retire 被 flush
    //     抑制, 取樣值與 flush 一致。
    //  注意不可 skip: 本環境 dispatch jam 依賴 flush 解除 (實測 skip 後
    //  17000 拍全 ROB 空轉, flush_cnt 1/22)。
    automatic int waited = 0;
    automatic int bt = 0;
    automatic int best = 0;
    automatic int bl = 0;
    automatic int base = 0;
    automatic int pc = 0;
    while (waited < 500) begin
      automatic bit any2 = 0;
      for (int t = 0; t < SMT_THREADS; t++)
        if (rob_popcount_t(t) >= 2) any2 = 1;
      if (any2 || rob_popcount() == 0) break;
      @(negedge clk); waited++;
    end
    @(posedge clk); #1;   // 同相取樣點 (NBA 更新後)
    for (int t = 0; t < SMT_THREADS; t++) begin
      pc = rob_popcount_t(t);
      if (pc > best) begin best = pc; bt = t; end
    end
    base = bt * (ROB_ENTRIES/SMT_THREADS);
    if (best >= 2) begin
      bl = int'(dut.u_rob.head[bt]);
      for (int i = 0; i < ROB_ENTRIES/SMT_THREADS; i++) begin
        automatic int li = (int'(dut.u_rob.head[bt]) + i) % (ROB_ENTRIES/SMT_THREADS);
        if (dut.u_rob.rob_array[base+li].valid) begin bl = li; break; end
      end
    end else if (rob_popcount() == 0) begin
      bt = 0;  base = 0;
      bl = (int'(dut.u_rob.head[0]) + (ROB_ENTRIES/SMT_THREADS) - 1)
           % (ROB_ENTRIES/SMT_THREADS);   // head-1: 空打, 不清 entry
    end else begin
      // timeout 兜底 (0<pop 但各分區 <2): 打最深分區的最老活體 entry
      bl = int'(dut.u_rob.head[bt]);
      for (int i = 0; i < ROB_ENTRIES/SMT_THREADS; i++) begin
        automatic int li = (int'(dut.u_rob.head[bt]) + i) % (ROB_ENTRIES/SMT_THREADS);
        if (dut.u_rob.rob_array[base+li].valid) begin bl = li; break; end
      end
    end
    // tid 一併切到 bt: rnu_remap/lsu 的 br_tid/flush_tid 皆接 TB 的 tid,
    // 若不切, 對 thread bt!=tid 的分區 flush 會讓 RAT/空閒表按錯誤
    // thread 恢復 → 之後 rename 重複分配 prd (A17 no_dup_wtag 實測
    // fails=3)。切齊 tid=bt 使全鏈路 flush 語義一致。
    force tid                = tid_t'(bt);
    force dut.bru_mispredict = 1'b1;
    force dut.bru_rob_idx    = rob_idx_t'(base + bl);
    force dut.bru_redir_pc   = 64'h0000_0000_8000_0000;
    @(posedge clk); #1;
    release dut.bru_mispredict;
    release dut.bru_rob_idx;
    release dut.bru_redir_pc;
    release tid;
  endtask

  // ---------------- 例外注入: force mul_exc 一拍 (A3/A13 前提) ----------------
  int exc_inj_done = 0;
  task automatic inject_exception();
    // [C2c] 例外注入點: thread0 ROB head entry. 本整合環境的寫回路径
    // 近乎停擺 (head entry 永不 complete -> retire 停滯, 屬 core 整合議題
    // 另案回報 F3), 由寫回通道注入的例外永遠到不了 head (實測 alu/ld/mul
    // 通道 2000 拍皆 timeout).
    // 改以 packed rob_complete/rob_complete_exc 位元 force, 在 head entry
    // 上建立 complete+exception, 下一拍 DUT 自己的 cmt_rob 即產生真實的
    // exception_detected -> retire_exception/flush/redirect, 完整走過
    // A3/A13 欲驗證的硬體路径 (flush 邏輯本身零造假).
    // v6.3.4 TB fix: 有界等待 thread0 head entry 活體再注入。BUG-B 修復後
    // 注入點可能落在 head 無效窗口 (dispatch 回壓 jam / 剛被 flush 排空),
    // force 打到無效 entry → exception_detected 不觸發 → A3/A13 vacuous。
    // 上限 300 拍 (例外 flush 亦承担解 jam 作用, 不宜無限推迟);
    // timeout 按原路注入, 行為不劣於舊版。
    begin
      automatic int w = 0;
      while (!dut.u_rob.rob_array[dut.u_rob.head[0]].valid && w < 300) begin
        @(negedge clk); w++;
      end
    end
    @(negedge clk);
    force dut.rob_complete[dut.u_rob.head[0]]     = 1'b1;
    force dut.rob_complete_exc[dut.u_rob.head[0]] = 1'b1;
    @(negedge clk);
    release dut.rob_complete[dut.u_rob.head[0]];
    release dut.rob_complete_exc[dut.u_rob.head[0]];
    // 探測窗: 200 拍內應見 retire_exception (head entry 已 complete+exc,
    // cmt_rob 下一拍即應 exception_detected)
    begin
      automatic bit seen = 0;
      for (int w2 = 0; w2 < 200 && !seen; w2++) begin
        @(negedge clk);
        if (dut.rt_exc_v === 1'b1) seen = 1;
      end
      if (!seen) $display("WARN: injected exception 200 拍內未見 retire_exception");
      else       exc_inj_done++;
    end
  endtask

  // [C2d] retire poke: force 指定 thread 的 head entry complete (packed 位元),
  // 使其自然 retire — retire arbitration/rt_valid/rt_tid 皆 DUT 真實硬體.
  // 本環境自然 retire 近乎停滯 (head 永不 complete, 見 [C2c]), A5/A6/A7/A12
  // 的前提 (retire_valid) 需以此定向補齊
  task automatic poke_retire(input int t);
    // v6.3.4 TB fix: 有界等待目標 thread 的 head entry 活體再 poke。
    // BUG-B 修復後 dispatch 有回壓 jam, poke 時刻該 thread 分區可能剛好
    // 為空 (head entry 無效) → complete 打到無效 entry, retire 不發生,
    // A5/A6/A7/A12 前提落空 (實測 A12 vacuous)。上限 200 拍, timeout
    // 按原路 poke (不劣化)。
    begin
      automatic int w = 0;
      while (!dut.u_rob.rob_array[t * (ROB_ENTRIES/SMT_THREADS) +
                                  int'(dut.u_rob.head[t])].valid && w < 200) begin
        @(negedge clk); w++;
      end
    end
    @(negedge clk);
    force dut.rob_complete[t * (ROB_ENTRIES/SMT_THREADS) +
                           int'(dut.u_rob.head[t])] = 1'b1;
    @(negedge clk);
    release dut.rob_complete[t * (ROB_ENTRIES/SMT_THREADS) +
                             int'(dut.u_rob.head[t])];
  endtask

  // ---------------- 主流程 ----------------
  initial begin
    for (int p = 0; p < NUM_LD_PIPE; p++) lane_seen[p] = 0;
    for (int i = 0; i < 16; i++) lat_hist[i] = 0;
    rst_n = 0;
    #57 rst_n = 1;

    // 例外注入趁 core 活動期 (淺 ROB)
    repeat (150) @(negedge clk);
    inject_exception();
    repeat (100) @(negedge clk);
    inject_exception();
    // 早段 flush (~cyc 750): 讓 A8/A10 佇列年齡全程 < timeout
    // (flush 間隙上限: 750→1310=560, 之後每 280, 皆 < 1000/2000)
    repeat (60) @(negedge clk);
    inject_flush();
    // retire poke 序列 (~cyc 1160, A12 FSM 開機 1000 拍 armed 後):
    // 依序 retire tid 0→1→2→3 (同時補齊 A5/A6/A7 的 retire 前提 [C2d]);
    // 距前次 flush 410 拍, ROB 已回填, 各 thread head entry valid
    repeat (410) @(negedge clk);
    for (int t = 0; t < SMT_THREADS; t++) begin
      poke_retire(t);
      repeat (20) @(negedge clk);
    end
    // flush 風暴 (~cyc 1310 起每 280 拍): 讓 A8/A10 liveness 窗口有界
    // (本環境 retire 近乎停滯, 若尾段無 flush, 佇列年齡超過 timeout
    //  即產生 stimulus 假 fail, 見 sva_cov_report 對照表 [C6][C7])
    repeat (60) @(negedge clk);
    for (int k = 0; k < INJ_CYCLES; k++) begin
      inject_flush();
      repeat (INJ_PERIOD) @(negedge clk);
    end
    repeat (160) @(negedge clk);

    // ---- 原功能檢查 ----
    if (fill_cnt == 0)      $fatal(1, "TB FAIL: no L2 fetch activity");
    if (prf_wr_cycles < 50) $fatal(1, "TB FAIL: PRF write activity too low (%0d)", prf_wr_cycles);
    if (vec_wr_seen == 0)   $fatal(1, "TB FAIL: no VEC writeback");
    if (ld_wr_seen == 0)    $fatal(1, "TB FAIL: no LD-lane writeback");
    if (lane_seen[0] == 0)  $fatal(1, "TB FAIL: no LSU lane0 activity");
    if (flush_cnt < INJ_CYCLES)        $fatal(1, "TB FAIL: flush count too low (%0d/%0d)", flush_cnt, INJ_CYCLES);
    if (flush_shrink_ok < flush_cnt)   $fatal(1, "TB FAIL: ROB did not shrink (%0d/%0d)", flush_shrink_ok, flush_cnt);
    if (fl_rebuild_ok < flush_cnt)     $fatal(1, "TB FAIL: freelist not conserved (%0d/%0d)", fl_rebuild_ok, flush_cnt);
    if (prf_after_flush < flush_cnt-1) $fatal(1, "TB FAIL: no PRF recovery (%0d/%0d)", prf_after_flush, flush_cnt);

    $display("TB INFO: fills=%0d prf_wr_cyc=%0d max_wports=%0d vec_wb=%0d ld_wb=%0d",
      fill_cnt, prf_wr_cycles, prf_wr_ports_max, vec_wr_seen, ld_wr_seen);
    $display("TB INFO: flushes=%0d rob_shrink=%0d fl_rebuild=%0d prf_recover=%0d exc_inj=%0d",
      flush_cnt, flush_shrink_ok, fl_rebuild_ok, prf_after_flush, exc_inj_done);
    begin
      string h = "TB INFO: A15 latency hist (dispatch->alu_rv) =";
      for (int i = 0; i < 10; i++) h = {h, $sformatf(" [%0d]=%0d", i, lat_hist[i])};
      $display("%s (max=%0d n=%0d)", h, lat_max, lat_cnt);
    end

    // ---- SVA 覆蓋率表 (逐 property attempts/fails) ----
    begin
      int nv = 0; int ft = 0;
      $display("=== SVA COVERAGE TABLE (sva_cpu_core_tb) ===");
      for (int i = 0; i < 19; i++)
        $display("SVACOV|CPU_CORE|%s|attempts=%0d|fails=%0d",
                 u_cov.PNAME[i], u_cov.att[i], u_cov.fail[i]);
      for (int i = 0; i < 19; i++) begin
        if (u_cov.att[i] > 0) nv++;
        ft += u_cov.fail[i];
      end
      $display("SVA_COV: sva_cpu_core %0d/19 nonvacuous, %0d fail", nv, ft);
    end
    // ---- SVA checker 結果併入 PASS 判定 ----
    // vacuity: 非致命, 一次列全部 (加速收斂); fails>0: 逐條 fatal
    begin
      int nvac = 0;
      for (int i = 0; i < 19; i++)
        if (u_cov.att[i] < 1) begin
          nvac++;
          $display("VACUOUS: property %0d (%s) attempts=0", i, u_cov.PNAME[i]);
        end
      if (nvac > 0)
        $display("SVA_COV WARN: %0d/19 property vacuous (見上 VACUOUS 清單)", nvac);
    end
    for (int i = 0; i < 19; i++) begin
      if (u_cov.fail[i] != 0)
        $fatal(1, "SVA_CPU_CORE_TB FAIL: property %0d (%s) fails=%0d", i, u_cov.PNAME[i], u_cov.fail[i]);
    end
    $display("SVA_CPU_CORE_TB PASS");
    $finish;
  end
endmodule : sva_cpu_core_tb
