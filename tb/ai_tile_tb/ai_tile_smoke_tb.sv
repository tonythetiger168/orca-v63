// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"

// AI tile smoke test: AIX GEMM 命令 -> GSCU 分派 -> cluster 完成
module ai_tile_smoke_tb;
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

  orca_v63_ai_tile #(.TILE_ID(0), .NCLUSTERS(1)) dut (
    .clk(clk), .rst_n(rst_n),
    .aix_uop(aix), .aix_valid(av), .aix_ready(ar),
    .noc_out(no), .noc_out_ready(1'b1),
    .noc_in(ni), .noc_in_valid(1'b0), .noc_in_ready(nir),
    .aix_irq(irq),
    .hbm_ck_t(hbm_ck_t), .hbm_ck_c(hbm_ck_c), .hbm_cs_n(hbm_cs_n));

  int cyc = 0;
  initial begin
    aix = '0; av = 0; ni = '0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    aix.opcode = OP_AIX;
    aix.imm    = 64'h0;              // AIX_OP_GEMM
    aix.rs1    = 5'd1; aix.rs2 = 5'd2; aix.rd = 5'd3;
    av = 1'b1; @(negedge clk); av = 1'b0;
    while (!irq && cyc < 5000) begin @(negedge clk); cyc = cyc + 1; end
    if (!irq) $fatal(1, "TB FAIL: AIX GEMM timeout");
    $display("TB PASS: AIX GEMM completed in %0d cycles", cyc);
    $finish;
  end
endmodule : ai_tile_smoke_tb
