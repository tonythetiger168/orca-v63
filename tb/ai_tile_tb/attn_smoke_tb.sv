// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.3 - AI Tile attention smoke test
// 發一個 attention 類 AIX uop (AIX_OP_ATTN_QK), 驗證 GSCU 將其分派到
// npu_attn_engine (而非 cluster), engine 跑完 QK^T->softmax->AV 流程後
// done 回報, GSCU drain 完成發 irq。
`include "orca_pkg.sv"

module attn_smoke_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  uop_t aix; logic av, ar, irq;
  flit_t no, ni;
  logic nir;
  logic [2:0] hbm_ck_t, hbm_ck_c, hbm_cs_n;
  logic hbm_init_done;

  orca_v63_ai_tile #(.TILE_ID(0), .NCLUSTERS(1)) dut (
    .clk(clk), .rst_n(rst_n),
    .aix_uop(aix), .aix_valid(av), .aix_ready(ar),
    .noc_out(no), .noc_out_ready(1'b1),
    .noc_in(ni), .noc_in_valid(1'b0), .noc_in_ready(nir),
    .aix_irq(irq),
    .hbm_ck_t(hbm_ck_t), .hbm_ck_c(hbm_ck_c), .hbm_cs_n(hbm_cs_n),
    .hbm_init_done(hbm_init_done));

  localparam logic [15:0] SEQ_LEN = 16;   // 一個 FlashAttention tile

  int cyc = 0;
  logic attn_started = 0;

  // 監控 attn engine 真的被分派啟動 (離開 IDLE)
  always @(posedge clk) begin
    if (rst_n && dut.attn_active) attn_started <= 1'b1;
  end

  initial begin
    aix = '0; av = 0; ni = '0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    // AIX uop: imm[7:0]=AIX opcode, imm[15:8]=flags, imm[18:16]=tile_id,
    //          imm[50:19]=length (這裡當 seq_len 用)
    aix.opcode = OP_AIX;
    aix.imm    = (64'(SEQ_LEN) << 19) | 64'(AIX_OP_ATTN_QK);
    aix.rs1    = 5'd1; aix.rs2 = 5'd2; aix.rd = 5'd3;
    av = 1'b1; @(negedge clk); av = 1'b0;
    while (!irq && cyc < 20000) begin @(negedge clk); cyc = cyc + 1; end
    if (!irq) $fatal(1, "TB FAIL: AIX ATTN timeout");
    if (!attn_started) $fatal(1, "TB FAIL: attn engine never dispatched");
    if (dut.u_attn.cycle_counter == 0)
      $fatal(1, "TB FAIL: attn engine did not run (cycle_counter=0)");
    $display("TB PASS: ATTN engine dispatched and completed in %0d cycles (engine busy %0d cycles)",
             cyc, dut.u_attn.cycle_counter);
    $display("TB INFO: hbm_init_done=%0b hbm_ck_t=%b hbm_cs_n=%b",
             hbm_init_done, hbm_ck_t, hbm_cs_n);
    $finish;
  end
endmodule : attn_smoke_tb
