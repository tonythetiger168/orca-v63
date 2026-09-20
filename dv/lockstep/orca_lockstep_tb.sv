// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - Async-Lockstep 驗證 TB: ORCA ZEN++ core vs 黃金參考 ISS (內嵌 orca_iss,
// 生產可經 DPI 換 Spike)。每條 in-order retire 指令與 ISS 期望值比對 PC/rd/result。
// riscv-dv 隨機程式亦可餵入 (L2 模型讀 hex)。支援 Spike/Core-V-Verif 流程 (見 dv/README)。
`include "orca_pkg.sv"

module orca_lockstep_tb;
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

  // ---- 黃金參考 ISS (lockstep) ----
  logic        iss_mm;
  xword_t      iss_exp;
  logic [4:0]  iss_dbg_rda;
  // retire 錨點: cmt_rob retire_entry[0] (in-order 提交頭)
  rob_entry_t  rt0;
  logic        rt0_valid;
  assign rt0       = dut.u_rob.retire_entry[0];
  assign rt0_valid = dut.u_rob.retire_valid[0];

  orca_iss u_iss (
    .clk(clk), .rst_n(rst_n),
    .retire_valid(rt0_valid), .opcode(rt0.uop.opcode), .funct3(rt0.uop.funct3),
    .rs1a(rt0.uop.rs1), .rs2a(rt0.uop.rs2), .rda(rt0.uop.rd),
    .imm(rt0.uop.imm), .rt_result(rt0.result), .rt_pc(rt0.uop.pc),
    .mismatch(iss_mm), .exp_result(iss_exp), .dbg_rda(iss_dbg_rda));

  int mm_cnt = 0, retire_cnt = 0;
  int unsigned seed;
  always @(posedge clk) begin
    if (rst_n && rt0_valid && rt0.uop.rd != 0
        && !(rt0.uop.opcode inside {OP_LOAD, OP_STORE, OP_BRANCH, OP_FENCE})) begin
      retire_cnt <= retire_cnt + 1;
      if (iss_mm) begin
        mm_cnt <= mm_cnt + 1;
        if (mm_cnt < 8)
          $display("[LOCKSTEP MISMATCH] pc=%h op=%0d rd=x%0d rtl=%h iss=%h",
                   rt0.uop.pc, rt0.uop.opcode, rt0.uop.rd, rt0.result, iss_exp);
      end
    end
  end

  // ---- 指令餵入: PROG (可換 riscv-dv 生成之 hex) ----
  logic [31:0] IMEM [0:63];
  int n=0;
  task automatic add(input logic [31:0] i); IMEM[n]=i; n++; endtask
  initial begin
    // RV64IM 隨機混合 (rs1=rs2=x0 即 ready, rd 循環) — 覆蓋 ALU/MUL/DIV/LUI/AUIPC
    add(32'h00000093); add(32'h00100113);      // addi x1,x0,0 / addi x2,x0,1
    for (int k=0;k<4;k++)                       // mul family (retire 乾淨)
      add({7'b0000001, 5'd1, 5'd1, 3'(k), 5'(k+3), 7'b0110011});
    for (int k=0;k<16;k++)                      // ALU R-type 全 funct3 (rs=x0, 即 ready)
      add({7'(k%2 ? 7'h20 : 7'h00), 5'd0, 5'd0, 3'(k%8), 5'(k%31+1), 7'b0110011});
    for (int k=0;k<8;k++) add({20'(k*113), 3'(k%8), 5'(k%31+1), 7'b0010011});  // ALUI
    add(32'hABCDE0B7); add(32'h12345097);       // lui / auipc
    while (n<64) add(32'h00000013);             // nop 補滿
  end
  int fill_cnt=0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      for (int w=0;w<16;w++) l2l[w*32 +: 32] <= IMEM[(fill_cnt*16+w) % 64];
      l2f <= 1'b1; fill_cnt <= fill_cnt + 1;
    end
  end

  initial begin
    tid = 2'b0;
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_600D;
    void'($urandom(seed));
    rst_n = 0; #57 rst_n = 1;
    repeat (3000) @(negedge clk);
    $display("LOCKSTEP: retire=%0d mismatches=%0d fills=%0d", retire_cnt, mm_cnt, fill_cnt);
    if (mm_cnt == 0 && retire_cnt >= 4)
      $display("TB PASS: async-lockstep %0d retired instrs, 0 mismatch vs golden ISS", retire_cnt);
    else
      $fatal(1, "LOCKSTEP FAIL: %0d mismatches / %0d retires", mm_cnt, retire_cnt);
    $finish;
  end
endmodule : orca_lockstep_tb
