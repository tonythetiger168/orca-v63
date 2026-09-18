// ORCA v6.3 ZEN++ - v6.3.3
// f1_frontend_tb: cov-f1 單元級 directed TB
// 目標: ifu_btb.sv line coverage 100%
// 策略: update allocation (done=0) / hit-existing update (done=1) /
//       lru 掃描兩方向 / lookup hit + miss (空表與 tag mismatch) / idle。
// 註: ifu_bpu.sv / ifu_tlb.sv 經 lead 決議列 N/A — 兩模組全設計無人例化,
//     且含 Verilator 5.006 不支援的 variable-width part-select
//     (ifu_bpu.sv:141,160 history[i +: len]; ifu_tlb.sv:30-33 qvpn[43 -: var]
//     與 va[sh-1:0]), 另有 bpu_info_t 全 repo 未定義, 皆屬 RTL 層缺陷,
//     留 v6.3.4 前端整合修復, 非 coverage 任務範圍。
`include "orca_pkg.sv"

module f1_frontend_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  int errors = 0;

  // ================= ifu_btb =================
  xword_t btb_pcq; logic btb_hit; xword_t btb_target; logic [1:0] btb_type;
  logic btb_upd_v; xword_t btb_upd_pc, btb_upd_tgt; logic [1:0] btb_upd_type;
  ifu_btb u_btb (.clk(clk), .rst_n(rst_n), .pc_q(btb_pcq), .hit(btb_hit),
    .target(btb_target), .btype(btb_type),
    .upd_valid(btb_upd_v), .upd_pc(btb_upd_pc), .upd_target(btb_upd_tgt),
    .upd_type(btb_upd_type));

  localparam xword_t P0 = 64'h0000_0000_8000_1000;

  initial begin
    btb_pcq = '0; btb_upd_v = 0; btb_upd_pc = '0; btb_upd_tgt = '0; btb_upd_type = '0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // lookup miss (空表)
    btb_pcq = P0; #1;
    if (btb_hit) begin $display("ERROR: btb 空表應 miss"); errors++; end
    @(negedge clk);
    // allocation (done=0 路徑, lru 掃描 w=0 即中)
    btb_upd_v = 1; btb_upd_pc = P0; btb_upd_tgt = 64'hAAAA_0000; btb_upd_type = 2'd1;
    @(negedge clk); btb_upd_v = 0;
    // lookup hit
    btb_pcq = P0; #1;
    if (!btb_hit || btb_target !== 64'hAAAA_0000 || btb_type !== 2'd1) begin
      $display("ERROR: btb 應 hit target=%h", btb_target); errors++; end
    @(negedge clk);
    // hit-existing update (done=1 路徑, if(!done) false 方向)
    btb_upd_v = 1; btb_upd_pc = P0; btb_upd_tgt = 64'hBBBB_0000; btb_upd_type = 2'd2;
    @(negedge clk); btb_upd_v = 0;
    btb_pcq = P0; #1;
    if (!btb_hit || btb_target !== 64'hBBBB_0000 || btb_type !== 2'd2) begin
      $display("ERROR: btb update 後應 hit 新 target"); errors++; end
    @(negedge clk);
    // 同 set 新 entry: lru 掃描兩方向 (lru[0]=1 false -> lru[1]=0 true)
    btb_upd_v = 1; btb_upd_pc = P0 + (64'h1 << 13); btb_upd_tgt = 64'hCCCC_0000; btb_upd_type = 2'd3;
    @(negedge clk); btb_upd_v = 0;
    // lookup 新 entry hit
    btb_pcq = P0 + (64'h1 << 13); #1;
    if (!btb_hit || btb_target !== 64'hCCCC_0000 || btb_type !== 2'd3) begin
      $display("ERROR: btb 第二 entry 應 hit"); errors++; end
    @(negedge clk);
    // 再裝三筆同 set (lru 全 1 後 vw 維持 0 的路徑) + upd_valid=0 idle
    btb_upd_v = 1; btb_upd_pc = P0 + (64'h2 << 13); @(negedge clk);
    btb_upd_pc = P0 + (64'h3 << 13); @(negedge clk);
    btb_upd_pc = P0 + (64'h4 << 13); @(negedge clk);
    btb_upd_pc = P0 + (64'h5 << 13); @(negedge clk); btb_upd_v = 0;
    // lookup tag mismatch (同 set 不同 tag -> miss) 與 upd_valid=0
    btb_pcq = P0 + (64'h7 << 13); #1; @(negedge clk);
    btb_pcq = '0; @(negedge clk);
    // 第二次 reset (rst_n 兩方向 toggle + reset loop 再跑)
    rst_n = 0; repeat (2) @(negedge clk);
    rst_n = 1; repeat (2) @(negedge clk);

    if (errors == 0) $display("TB PASS: f1_frontend_tb (ifu_btb)");
    else             $display("TB FAIL: f1_frontend_tb errors=%0d", errors);

    // ---- cov-f1 toggle: ifu_btb 零命中 bits (全功能性, 不 poke comb) ----
    // target (comb output): update entry target='1 後 lookup (0->1),
    //   再 update target='0 後 lookup (1->0), 全 64 bits 真實翻動。
    btb_upd_v = 1; btb_upd_pc = P0; btb_upd_tgt = '1; btb_upd_type = 2'd1;
    @(negedge clk); btb_upd_v = 0;
    btb_pcq = P0; #1;                                        // target = '1 (0->1)
    btb_upd_v = 1; btb_upd_tgt = '0; @(negedge clk); btb_upd_v = 0;
    #1;                                                      // target = '0 (1->0)
    // pc_q/upd_pc/upd_target input toggle (upd_valid=0 不改狀態);
    // set/tq 為 pc_q 衍生 comb wire, 隨 pc_q 翻動命中。
    btb_pcq = '1; #1; btb_pcq = '0; #1;                      // pc_q + set + tq
    btb_upd_pc = '1; btb_upd_tgt = '1; #1;
    btb_upd_pc = '0; btb_upd_tgt = '0; #1;                   // upd_pc + upd_target
    repeat (3) @(negedge clk);
    $finish;
  end
endmodule : f1_frontend_tb
