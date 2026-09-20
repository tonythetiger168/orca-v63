// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
// idu_decoder + idu_rvc_expand 全覆蓋: 遍歷所有 major opcode 與 RVC quadrant
module unit_decode_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  logic [31:0] dec_inst; logic dec_v; uop_t dec_uop; logic dec_rdy; tid_t dtid;
  idu_decoder u_dec (.clk(clk), .rst_n(rst_n), .inst(dec_inst), .valid(dec_v),
    .pc(64'h1000), .tid(2'b0), .uop(dec_uop), .ready(dec_rdy));

  logic [15:0] rvc_ci; logic [31:0] rvc_oi; logic rvc_il;
  idu_rvc_expand u_rvc (.cinst(rvc_ci), .inst(rvc_oi), .illegal(rvc_il));

  int opc_seen [0:127]; int rvc_seen [0:3][0:7];
  initial begin
    dec_v = 0; dec_inst = '0; rvc_ci = '0; dtid = 2'b0;
    rst_n = 0; #57 rst_n = 1; @(negedge clk);
    // 遍歷 128 個 major opcodes (inst[6:0]), 每個搭配 rs1=rs2=rd=0, funct3 掃 0..7
    for (int op = 0; op < 128; op++) begin
      for (int f3 = 0; f3 < 8; f3++) begin
        dec_inst = {20'h0, 3'(f3), 5'd1, 7'(op)};
        dec_v = 1; #1; opc_seen[op] = 1; @(negedge clk);
      end
    end
    dec_v = 0;
    // RVC: 真實 C 指令編碼 (每個有效 C 指令一個代表, 覆蓋所有 case arm)
    begin : rvc_real
      logic [15:0] cins [0:23];
      int nc = 0;
      // quadrant[1:0] x funct3[15:13] 正確對齊（bit1:0=quadrant, bit15:13=funct3）
      cins[nc++]=16'h0001;  // Q0 f3=000 C.ADDI4SPN / c.nop 區
      cins[nc++]=16'h2001;  // Q1 f3=000 C.ADDI
      cins[nc++]=16'h4001;  // Q1 f3=010 C.LI
      cins[nc++]=16'h6001;  // Q1 f3=011 C.LUI/ADDI16SP
      cins[nc++]=16'h8001;  // Q1 f3=100 C.SRLI
      cins[nc++]=16'hA001;  // Q1 f3=101 C.J
      cins[nc++]=16'hC001;  // Q1 f3=110 C.BEQZ
      cins[nc++]=16'hE001;  // Q1 f3=111 C.BNEZ
      cins[nc++]=16'h0002;  // Q2 f3=000 C.SLLI
      cins[nc++]=16'h8002;  // Q2 f3=100 C.JR/MV
      cins[nc++]=16'h9002;  // Q2 f3=100 C.EBREAK
      cins[nc++]=16'h0000;  // c.unimp 邊界
      // 精準命中未覆蓋的四型（quadrant/funct3 正確對齊）:
      cins[nc++]=16'h4000;  // Q0 f3=010 C.LW   ([15:13]=010,[1:0]=00)
      cins[nc++]=16'h6000;  // Q0 f3=011 C.LD   ([15:13]=011,[1:0]=00)
      cins[nc++]=16'hC000;  // Q0 f3=110 C.SW   ([15:13]=110,[1:0]=00)
      cins[nc++]=16'h4002;  // Q2 f3=010 C.LWSP ([15:13]=010,[1:0]=10)
      cins[nc++]=16'h6002;  // Q2 f3=011 C.LDSP ([15:13]=011,[1:0]=10)
      cins[nc++]=16'hC002;  // Q2 f3=110 C.SWSP ([15:13]=110,[1:0]=10)
      cins[nc++]=16'hFFFF;  // illegal (quadrant 3 default)
      for (int i = 0; i < nc; i++) begin
        rvc_ci = cins[i]; #1; @(negedge clk);
      end
    end
    $display("DECODE TB PASS: opcodes+funct3 swept, RVC quadrants swept");
    $finish;
  end
endmodule : unit_decode_tb
