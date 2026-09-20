// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
module unit_dtlb_tb;
  import orca_pkg::*;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end

  xword_t va; logic qv; logic hit; paddr_t pa;
  logic wrq; xword_t wa; logic wrv; xword_t wrd;
  logic fv; xword_t fva; paddr_t fpa;
  lsu_dtlb u_dtlb (.clk(clk), .rst_n(rst_n), .va(va), .q_valid(qv), .hit(hit), .pa(pa),
    .walk_req(wrq), .walk_addr(wa), .walk_rvalid(wrv), .walk_rdata(wrd),
    .fill_valid(fv), .fill_va(fva), .fill_pa(fpa));
  int n=0;
  initial begin
    va='0; qv=0; wrv=0; wrd='0; fv=0; fva='0; fpa='0;
    rst_n=0; #57 rst_n=1; @(negedge clk);
    // 走訪: miss -> walk req -> walk rvalid -> fill -> hit
    for (int i=0;i<20;i++) begin
      va = 64'h8000_0000 + i*64; qv=1; @(negedge clk);
      // 等 walk_req
      begin int g=0; while(!wrq && g<10) begin @(negedge clk); g++; end end
      wrv=1; wrd = 64'hC000_0000 + i*64; @(negedge clk); wrv=0; @(negedge clk);
      qv=0; @(negedge clk);
    end
    // fill 直接驅動（覆蓋 fill_* 埠）
    for (int i=0;i<10;i++) begin
      fva = 64'h9000_0000 + i*128; fpa = 64'hD000_0000 + i*128; fv=1; @(negedge clk); fv=0; @(negedge clk);
    end
    // fill 後同位址查詢 (hit)
    for (int i=0;i<10;i++) begin
      va = 64'h9000_0000 + i*128; qv=1; #1; @(negedge clk); qv=0; @(negedge clk);
    end
    $display("DTLB TB PASS"); $finish;
  end
endmodule : unit_dtlb_tb
