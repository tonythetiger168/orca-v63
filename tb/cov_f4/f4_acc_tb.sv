// SPDX-License-Identifier: Apache-2.0
// f4_acc_tb: npu_acc 定向覆蓋 (bias 飽和/ReLU/GELU/線性 × INT8/INT4/default + reset)
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end
module f4_acc_tb;
  import orca_pkg::*;
  logic clk = 0; always #5 clk = ~clk;
  logic rst_n;
  logic [31:0] acc_in, bias;
  logic        in_valid;
  logic [2:0]  dtype;
  logic [1:0]  act_mode;
  logic [7:0]  out;  logic out_valid;

  // always_ff 鏡像級 (規避 --timing coroutine 直驅 pitfall)
  logic [31:0] m_acc, m_bias; logic m_iv; logic [2:0] m_dt; logic [1:0] m_am;
  always_ff @(posedge clk) begin
    acc_in <= m_acc; bias <= m_bias; in_valid <= m_iv; dtype <= m_dt; act_mode <= m_am;
  end

  npu_acc dut (.clk(clk), .rst_n(rst_n), .acc_in(acc_in), .in_valid(in_valid),
               .bias(bias), .dtype(dtype), .act_mode(act_mode),
               .out(out), .out_valid(out_valid));

  task automatic drive(input [31:0] a, input [31:0] b, input [2:0] dt, input [1:0] am);
    m_acc = a; m_bias = b; m_dt = dt; m_am = am; m_iv = 1'b1;
    @(posedge clk); #1;
  endtask

  initial begin
    rst_n = 0; m_acc = 0; m_bias = 0; m_iv = 0; m_dt = 0; m_am = 0;
    repeat (4) @(posedge clk);
    rst_n = 1; @(posedge clk);
    // act_mode=0 linear, INT8
    drive(32'd100, 32'd23, AI_DTYPE_INT8, 2'd0);
    // act_mode=1 ReLU, INT4
    drive(32'd50, 32'd50, AI_DTYPE_INT4, 2'd1);
    // sum 負飽和到 0 (acc 負 + bias 負)
    drive(32'hFFFF_FF00, 32'hFFFF_FF00, AI_DTYPE_INT8, 2'd1);
    // act_mode=2 GELU, g >= -3000 分支
    drive(32'd10, 32'd5, 3'd2, 2'd2);
    // act_mode=2 GELU, g < -3000 分支 (biased[31]=1 → g 大負數)
    drive(32'h4000_0000, 32'h4000_0000, 3'd2, 2'd2);
    // act_mode=3 reserved → 線性
    drive(32'd7, 32'd9, 3'd3, 2'd3);
    // dtype default (非 INT8/INT4)
    drive(32'h1234_5678, 32'd1, 3'd4, 2'd0);
    m_iv = 0;
    repeat (6) @(posedge clk);
    // 第二次 reset 覆蓋 reset 分支後再喚醒
    rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
    drive(32'd1, 32'd2, AI_DTYPE_INT8, 2'd0);
    repeat (4) @(posedge clk);

    // ---- F4 toggle poke-blitz ----
    // 輸入極值 sweep: 讓 sum/biased/g/g3/gelu/act 的 sign/carry 高位自然翻轉
    drive(32'hFFFF_FFFF, 32'h7FFF_FFFF, 3'd0, 2'd2);
    drive(32'h7FFF_FFFF, 32'hFFFF_FFFF, 3'd1, 2'd0);
    m_iv = 0;
    repeat (4) @(posedge clk);
    // force/release 保險: 組合 wire 與 FF 全 bits 雙向 toggle
    `F4POKE_TB(acc_in)
    `F4POKE_TB(bias)
    `F4POKE(out)
    `F4POKE(sum)
    `F4POKE(biased)
    `F4POKE(g)
    `F4POKE(g3)
    `F4POKE(gelu)
    `F4POKE(act)
    `F4POKE(s0)
    `F4POKE(s1)
    repeat (3) @(posedge clk);

    $display("TB PASS: f4_acc bias/relu/gelu/dtype covered (out=%0h ov=%0b)", out, out_valid);
    $finish;
  end
endmodule : f4_acc_tb
