// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.4 coverage sweep
`include "orca_pkg.sv"

// Opcode-sweep coverage TB: 透過 fetch 送涵蓋所有解碼 arm / EXU funct3 變體 /
// RVC 壓縮格式 / 分支條件 / trap 的豐富指令流,拉升 idu_decoder / idu_rvc_expand /
// exu_mul / exu_bru / cmt_trap / exu_fpu / exu_vec 覆蓋率。
// 所有 rs1/rs2 = x0 (排程器 insert 即 ready); rd 循環以製造 rename 活動。
module cpu_opcode_sweep_tb;
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

  // ---------------- 指令建構輔助 ----------------
  function automatic logic [31:0] R (input logic [6:0] f7, input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {f7, 5'd0, 5'd0, f3, rd, op};            // rs2=0, rs1=0
  endfunction
  function automatic logic [31:0] I (input logic [11:0] imm, input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {imm, 5'd0, f3, rd, op};                 // rs1=0
  endfunction
  function automatic logic [31:0] S (input logic [11:0] imm, input logic [2:0] f3, input logic [6:0] op);
    return {imm[11:5], 5'd0, 5'd0, f3, imm[4:0], op};
  endfunction
  function automatic logic [31:0] B (input logic [2:0] f3);
    return {1'b0, 6'd0, 5'd0, 5'd0, f3, 1'b0, 4'd0, 1'b0, 7'b1100011}; // beq..bgeu
  endfunction
  function automatic logic [31:0] U (input logic [19:0] imm, input logic [4:0] rd, input logic [6:0] op);
    return {imm, rd, op};
  endfunction
  function automatic logic [31:0] J (input logic [4:0] rd);
    return {1'b0, 10'd4, 1'b0, 8'd0, rd, 7'b1101111}; // jal rd, +8
  endfunction

  localparam int IMEM_N = 128;
  logic [31:0] IMEM [0:IMEM_N-1];
  int n_insn = 0;
  task automatic add(input logic [31:0] ins);
    IMEM[n_insn] = ins; n_insn++;
  endtask

  // ---------------- 填充指令記憶體 ----------------
  initial begin
    // -- LUI / AUIPC --
    add(U(20'hABCDE, 5'd1, 7'b0110111));            // lui
    add(U(20'h12345, 5'd2, 7'b0010111));            // auipc
    // -- JAL / JALR --
    add(J(5'd3)); add(I(12'd8, 3'b000, 5'd4, 7'b1100111)); // jal / jalr
    // -- 6 條件分支 (exu_bru 全 funct3) --
    for (int f = 0; f < 6; f++) add(B(3'(f)));
    // -- LOAD 全 funct3 (LB/LH/LW/LD/LBU/LHU/LWU) --
    for (int f = 0; f < 7; f++) add(I(12'd16, 3'(f), 5'd5, 7'b0000011));
    // -- STORE 全 funct3 (SB/SH/SW/SD) --
    for (int f = 0; f < 4; f++) add(S(12'd16, 3'(f), 7'b0100011));
    // -- ALUI 全 funct3 (ADDI/SLTI/SLTIU/XORI/ORI/ANDI + shifts) --
    for (int f = 0; f < 8; f++) add(I(12'd5, 3'(f), 5'd6, 7'b0010011));
    add(I(12'h400, 3'b001, 5'd6, 7'b0010011));      // slli
    add(I(12'h450, 3'b101, 5'd6, 7'b0010011));      // srli
    add(I(12'h450, 3'b101, 5'd6, 7'b0010011));      // srai (funct6 overlap)
    // -- ALU 全 funct3 (ADD/SUB/SLT/XOR/OR/AND/SLL/SRL/SRA) --
    for (int f = 0; f < 8; f++) add(R(7'b0000000, 3'(f), 5'd7, 7'b0110011));
    add(R(7'b0100000, 3'b000, 5'd7, 7'b0110011));   // sub
    add(R(7'b0100000, 3'b101, 5'd7, 7'b0110011));   // sra
    // -- M ext 全 funct3 (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU) --
    for (int f = 0; f < 8; f++) add(R(7'b0000001, 3'(f), 5'd8, 7'b0110011));
    // -- FENCE / FENCE.I --
    add(I(12'd0, 3'b000, 5'd0, 7'b0001111));
    add(I(12'd0, 3'b001, 5'd0, 7'b0001111));
    // -- SYSTEM: ECALL / EBREAK (觸發 cmt_trap) / CSR* --
    add(I(12'd0,  3'b000, 5'd0, 7'b1110011));      // ecall
    add(I(12'd1,  3'b000, 5'd0, 7'b1110011));      // ebreak
    add(I(12'h305,3'b001, 5'd9, 7'b1110011));      // csrrw
    add(I(12'h305,3'b010, 5'd9, 7'b1110011));      // csrrs
    add(I(12'h305,3'b011, 5'd9, 7'b1110011));      // csrrc
    add(I(12'h305,3'b101, 5'd9, 7'b1110011));      // csrrwi
    add(I(12'h305,3'b110, 5'd9, 7'b1110011));      // csrrsi
    add(I(12'h305,3'b111, 5'd9, 7'b1110011));      // csrrci
    // -- AMO (LR/SC/SWAP/ADD/...) --
    add(R(7'b0001000, 3'b010, 5'd10, 7'b0101111));  // lr.w
    add(R(7'b0001100, 3'b010, 5'd10, 7'b0101111));  // sc.w
    add(R(7'b0000100, 3'b010, 5'd10, 7'b0101111));  // amoswap.w
    add(R(7'b0000000, 3'b010, 5'd10, 7'b0101111));  // amoadd.w
    add(R(7'b0010000, 3'b010, 5'd10, 7'b0101111));  // amoxor.w
    // -- FP (OP-FP: fadd/fmul/fsgnj/fmin/fmax) --
    add(R(7'b0000000, 3'b000, 5'd11, 7'b1010011));  // fadd.s
    add(R(7'b0001000, 3'b000, 5'd11, 7'b1010011));  // fmul.s
    add(R(7'b0010000, 3'b000, 5'd11, 7'b1010011));  // fsgnj.s
    add(R(7'b0010100, 3'b000, 5'd11, 7'b1010011));  // fmin.s
    add(R(7'b0010100, 3'b001, 5'd11, 7'b1010011));  // fmax.s
    add(I(12'd0, 3'b000, 5'd11, 7'b1000011));       // flw? (OP-FP load path)
    add(S(12'd0, 3'b000, 7'b1000111));              // fsw
    // -- VEC: vsetvli + vector op --
    add(I(12'h020, 3'b111, 5'd0, 7'b1010111));      // vsetvli
    add(R(7'b0000000, 3'b000, 5'd12, 7'b1010111));  // vadd (OP-V funct6!=0)
    add(I(12'd0, 3'b000, 5'd12, 7'b0000111));       // vle? (OP-V load)
    add(S(12'd0, 3'b000, 7'b0100111));              // vse
    // -- AIX custom-0 --
    add(I(12'h001, 3'b000, 5'd13, 7'b0001011));
    // -- RVC 壓縮格式 (16-bit; 取低 16 位, fetch 偵測 [1:0]!=11) --
    IMEM[n_insn] = 16'h0001; n_insn++;              // c.nop (c.addi x0,0)
    IMEM[n_insn] = 16'h0081; n_insn++;              // c.jr? (c.mv x1,x0 區)
    IMEM[n_insn] = 16'h0023; n_insn++;              // c.lw 區
    IMEM[n_insn] = 16'h00A2; n_insn++;              // c.swsp 區
    IMEM[n_insn] = 16'h4101; n_insn++;              // c.li/c.addi16sp 區
    IMEM[n_insn] = 16'h8082; n_insn++;              // c.jr x1
    IMEM[n_insn] = 16'h9002; n_insn++;              // c.ebreak 區
    // -- illegal (default arm) --
    add(32'hFFFFFFFF);
    add(32'h00000000);                              // also c.unimp-ish
    // 用 NOP 補滿
    while (n_insn < IMEM_N) begin IMEM[n_insn] = 32'h00000013; n_insn++; end
  end

  // ---------------- L2 模型: 循環供指 ----------------
  int fill_cnt = 0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      for (int w = 0; w < 16; w++)
        l2l[w*32 +: 32] <= IMEM[(fill_cnt*16 + w) % IMEM_N];
      l2f      <= 1'b1;
      fill_cnt <= fill_cnt + 1;
    end
  end

  // ---------------- 計數探針 ----------------
  int dec_uop_seen [0:27];  // opcode_type_t 0..26 出現次數
  int trap_seen = 0, flush_seen = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int s = 0; s < 12; s++)
        if (dut.rn_ov[s]) dec_uop_seen[int'(dut.rn_out[s].opcode)] <= dec_uop_seen[int'(dut.rn_out[s].opcode)] + 1;
      if (dut.flush_valid_core) flush_seen <= flush_seen + 1;
    end
  end

  // ---------------- 測試主體 ----------------
  int distinct_ops = 0;
  initial begin
    tid = 2'b0;
    rst_n = 0;
    #57 rst_n = 1;
    // 跑足夠週期讓整個 IMEM 循環多遍、各 EXU 與 trap 累積覆蓋
    repeat (3000) @(negedge clk);
    for (int o = 0; o < 27; o++) if (dec_uop_seen[o] > 0) distinct_ops++;
    $display("SWEEP distinct_opcodes=%0d flush=%0d fill=%0d", distinct_ops, flush_seen, fill_cnt);
    if (distinct_ops >= 20 && fill_cnt > 50)
      $display("TB PASS: opcode sweep covered %0d opcodes", distinct_ops);
    else
      $fatal(1, "TB FAIL: only %0d opcodes, fill=%0d", distinct_ops, fill_cnt);
    $finish;
  end
endmodule : cpu_opcode_sweep_tb
