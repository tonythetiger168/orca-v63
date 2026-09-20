// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - Constrained-Random (CRT) TB: SystemVerilog class randomize()
// 約束隨機測試 + 多 seed。class 定義於 module 內部 (避開 $unit scope 與 coverage 衝突)。
`include "orca_pkg.sv"

module cpu_crt_tb;
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

  // std::randomize() 隨機化 (無 class, 避開 Vclpkg+coverage 衝突)
  logic [2:0] r_funct3;  logic [6:0] r_funct7;
  logic [4:0] r_rs1, r_rs2, r_rd;
  task automatic gen_one(output logic [31:0] insn);
    logic [6:0] opc;  int w;
    // 注意: 本工具 5.006 不支援 std randomize/class randomize+coverage, 改用 urandom_range
    // (class randomize() 版本見 cpu_crt_class_tb.sv, 供 VCS/非 coverage 模擬)
    r_funct3 = 3'($urandom_range(0, 7));
    r_rs1    = 5'($urandom_range(0, 31));
    r_rs2    = 5'($urandom_range(0, 31));
    r_rd     = 5'($urandom_range(1, 31));   // rd != 0
    // 加權 opcode (40/25/10/8/10/4/3%)
    w = $urandom_range(0,99);
    if      (w < 40) opc = 7'b0110011;
    else if (w < 65) opc = 7'b0010011;
    else if (w < 75) opc = 7'b0000011;
    else if (w < 83) opc = 7'b0100011;
    else if (w < 93) opc = 7'b1100011;
    else if (w < 97) opc = 7'b0111011;
    else             opc = 7'b1010111;
    if (opc == 7'b0110011 || opc == 7'b0111011) begin
      r_funct7 = ($urandom_range(0,99) < 25) ? 7'b0000001 : (($urandom_range(0,99) < 60) ? 7'b0000000 : 7'b0100000);
      insn = {r_funct7, r_rs2, r_rs1, r_funct3, r_rd, opc};
    end else if (opc == 7'b0010011 || opc == 7'b0000011)
      insn = {$urandom_range(0,4095), r_rs1, r_funct3, r_rd, opc};
    else if (opc == 7'b0100011)
      insn = {$urandom_range(0,4095), r_rs2, r_rs1, r_funct3, $urandom_range(0,31), opc};
    else if (opc == 7'b1100011)
      insn = {$urandom_range(0,1023), r_rs2, r_rs1, r_funct3, $urandom_range(0,63), opc};
    else
      insn = {r_funct7, r_rs2, r_rs1, r_funct3, r_rd, opc};
  endtask

  // 隨機種子
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_6332;
    $display("CRT SEED=%0d", seed);
    void'($urandom(seed));
  end

  logic [31:0] crt_imem [0:255];
  int crt_n = 0;
  initial begin
    for (int i = 0; i < 256; i++) gen_one(crt_imem[i]);
    crt_n = 256;
  end

  int fill_cnt = 0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      for (int w = 0; w < 16; w++) l2l[w*32 +: 32] <= crt_imem[(fill_cnt*16 + w) % crt_n];
      l2f <= 1'b1;
      fill_cnt <= fill_cnt + 1;
    end
  end

  int opc_cnt [0:127];
  int exc_cnt = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int sl = 0; sl < 12; sl++)
        if (dut.rn_ov[sl])
          opc_cnt[int'(dut.rn_out[sl].opcode)] <= opc_cnt[int'(dut.rn_out[sl].opcode)] + 1;
      if (dut.u_rob.retire_exception) exc_cnt <= exc_cnt + 1;
    end
  end

  int distinct_opc = 0;
  initial begin
    tid = 2'b0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4000) @(negedge clk);
    for (int o = 0; o < 128; o++) if (opc_cnt[o] > 0) distinct_opc++;
    $display("CRT: fill=%0d distinct_opc=%0d retire_exc=%0d", fill_cnt, distinct_opc, exc_cnt);
    if (fill_cnt > 30 && distinct_opc >= 4)
      $display("TB PASS: CRT %0d random instructions, %0d opcodes, exc=%0d", crt_n, distinct_opc, exc_cnt);
    else
      $fatal(1, "CRT FAIL: fill=%0d distinct=%0d", fill_cnt, distinct_opc);
    $finish;
  end
endmodule : cpu_crt_tb
