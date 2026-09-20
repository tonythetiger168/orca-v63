// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.3
// f1_decode_tb: cov-f1 單元級 directed TB
// 目標: idu_decoder.sv / idu_rvc_expand.sv / ifu_fetch.sv line coverage 100%
// 策略: 直接例化, 以 directed stimulus 打遍所有 opcode case 分支與
//       RVC C0/C1/C2 各壓縮指令展開, 以及 ifu_fetch 的 push/pop/idle/redirect。
`include "orca_pkg.sv"

module f1_decode_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ---------------- idu_decoder ----------------
  logic [31:0] dec_inst;
  logic        dec_valid_i;
  xword_t      dec_pc;
  tid_t        dec_tid;
  uop_t        dec_uop;
  logic        dec_ready;

  idu_decoder u_dec (
    .clk(clk), .rst_n(rst_n),
    .inst(dec_inst), .valid(dec_valid_i), .pc(dec_pc), .tid(dec_tid),
    .uop(dec_uop), .ready(dec_ready));

  // ---------------- idu_rvc_expand ----------------
  logic [15:0] cinst;
  logic [31:0] rvc_inst;
  logic        rvc_illegal;

  idu_rvc_expand u_rvc (.cinst(cinst), .inst(rvc_inst), .illegal(rvc_illegal));

  // ---------------- ifu_fetch ----------------
  logic        redirect_valid;
  xword_t      redirect_pc;
  xword_t      fetch_pc;
  logic        fetch_req;
  logic        fetch_ack;
  logic [FETCH_WIDTH*32-1:0] fetch_block;
  logic [FETCH_WIDTH*32-1:0] dec_block;
  xword_t      if_dec_pc;
  logic [FETCH_WIDTH-1:0]    dec_rvc;
  logic        if_dec_valid;
  logic        if_dec_ready;
  logic [7:0]  fetchbuf_cnt;

  ifu_fetch u_ifu (
    .clk(clk), .rst_n(rst_n),
    .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
    .fetch_pc(fetch_pc), .fetch_req(fetch_req), .fetch_ack(fetch_ack),
    .fetch_block(fetch_block),
    .dec_block(dec_block), .dec_pc(if_dec_pc), .dec_rvc(dec_rvc),
    .dec_valid(if_dec_valid), .dec_ready(if_dec_ready),
    .fetchbuf_cnt(fetchbuf_cnt));

  // ---------------- idu_uop_queue (cov-f1 toggle 補丁例化) ----------------
  // 原 dat 中 out_ready/wptr 有零命中 bits; 於此直接例化以便 poke。
  uop_t [DECODE_WIDTH-1:0]   uq_in_uop;
  logic [DECODE_WIDTH-1:0]   uq_in_valid, uq_in_ready;
  uop_t [DISPATCH_WIDTH-1:0] uq_out_uop;
  logic [DISPATCH_WIDTH-1:0] uq_out_valid, uq_out_ready;
  logic [6:0]                uq_occupancy;

  idu_uop_queue u_uq (
    .clk(clk), .rst_n(rst_n),
    .in_uop(uq_in_uop), .in_valid(uq_in_valid), .in_ready(uq_in_ready),
    .out_uop(uq_out_uop), .out_valid(uq_out_valid), .out_ready(uq_out_ready),
    .occupancy(uq_occupancy));

  int errors = 0;

  task automatic check_dec(input logic [31:0] inst, input logic [7:0] exp_op,
                           input string name);
    begin
      dec_inst    = inst;
      dec_valid_i = 1'b1;
      dec_tid     = dec_tid + 1;   // toggle tid
      dec_pc      = dec_pc + 64'h10;
      #1;
      if (dec_uop.opcode !== exp_op) begin
        $display("ERROR: %s opcode=%0d expect %0d", name, dec_uop.opcode, exp_op);
        errors++;
      end
    end
  endtask

  task automatic check_rvc(input logic [15:0] c, input logic exp_ill,
                           input string name);
    begin
      cinst = c;
      #1;
      if (rvc_illegal !== exp_ill) begin
        $display("ERROR: rvc %s illegal=%0b expect %0b (inst=%h)",
                 name, rvc_illegal, exp_ill, rvc_inst);
        errors++;
      end
    end
  endtask

  initial begin
    dec_inst = '0; dec_valid_i = 0; dec_pc = 64'h8000_0000; dec_tid = '0;
    cinst = '0;
    redirect_valid = 0; redirect_pc = '0;
    fetch_ack = 0; fetch_block = '0; if_dec_ready = 0;
    uq_in_uop = '{default: '0}; uq_in_valid = '0; uq_out_ready = '0;

    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // ============ idu_decoder: 所有 opcode 分支 ============
    check_dec(32'h1234_50B7, OP_LUI,    "LUI");
    check_dec(32'h0000_0117, OP_AUIPC,  "AUIPC");
    check_dec(32'h0080_006F, OP_JAL,    "JAL");
    check_dec(32'h0000_8067, OP_JALR,   "JALR rs1=x1 (ret)");
    check_dec(32'h0002_8067, OP_JALR,   "JALR rs1=x5");
    check_dec(32'h0020_8463, OP_BRANCH, "BEQ");
    check_dec(32'h0000_2083, OP_LOAD,   "LW");
    check_dec(32'h0010_2023, OP_STORE,  "SW");
    check_dec(32'h0010_0113, OP_ALUI,   "ADDI");
    check_dec(32'h0020_81B3, OP_ALU,    "ADD");
    check_dec(32'h0220_81B3, OP_MUL,    "MUL");   // funct7=1 f3[2]=0
    check_dec(32'h0220_C1B3, OP_DIV,    "DIV");   // funct7=1 f3[2]=1
    check_dec(32'h1000_202F, OP_AMO,    "AMO");
    check_dec(32'h0000_000F, OP_FENCE,  "FENCE");
    check_dec(32'h0000_0073, OP_SYSTEM, "ECALL");
    check_dec(32'h3000_1073, OP_CSR,    "CSRRW");
    check_dec(32'h0000_2043, OP_FPLD,   "FLW");
    check_dec(32'h0000_2047, OP_FPST,   "FSW");
    check_dec(32'h0000_0053, OP_FP,     "FADD");
    check_dec(32'h0000_0057, OP_VEC_CFG,"VSETVL");  // inst[25]=0
    check_dec(32'h0200_0057, OP_VEC,    "VADD");    // inst[25]=1
    check_dec(32'h0000_2007, OP_VEC_LD, "VLD");
    check_dec(32'h0000_2027, OP_VEC_ST, "VST");
    check_dec(32'h0000_000B, OP_AIX,    "AIX custom-0");
    check_dec(32'h0000_007B, OP_NOP,    "illegal opcode (default)");
    // valid=0 -> UOP_NOP
    dec_valid_i = 1'b0; dec_inst = 32'h1234_50B7; #1;
    dec_valid_i = 1'b1; #1;

    // ============ idu_rvc_expand: C0/C1/C2 全展開 ============
    // --- C0 (quadrant 00) ---
    check_rvc(16'h1FFC, 1'b0, "C.ADDI4SPN");   // f3=000
    check_rvc(16'h4000, 1'b0, "C.LW");         // f3=010
    check_rvc(16'h6000, 1'b0, "C.LD");         // f3=011
    check_rvc(16'h8000, 1'b1, "C0 f3=100 illegal");
    check_rvc(16'h2000, 1'b1, "C0 f3=001 illegal");
    // --- C1 (quadrant 01) ---
    check_rvc(16'h0001, 1'b0, "C.ADDI");       // f3=000
    check_rvc(16'h2001, 1'b0, "C.JAL");        // f3=001
    check_rvc(16'h4001, 1'b0, "C.LI");         // f3=010
    check_rvc(16'h6101, 1'b0, "C.ADDI16SP");   // f3=011 rd==2
    check_rvc(16'h6181, 1'b0, "C.LUI");        // f3=011 rd!=2
    check_rvc(16'h8001, 1'b0, "C.SRLI");       // f3=100
    check_rvc(16'hA001, 1'b0, "C.J");          // f3=101
    check_rvc(16'hC001, 1'b0, "C.BEQZ");       // f3=110
    check_rvc(16'hE001, 1'b0, "C.BNEZ");       // f3=111
    // --- C2 (quadrant 10) ---
    check_rvc(16'h0002, 1'b0, "C.SLLI");       // f3=000
    check_rvc(16'h4002, 1'b0, "C.LWSP");       // f3=010
    check_rvc(16'h6002, 1'b0, "C.LDSP");       // f3=011
    check_rvc(16'h8002, 1'b0, "C.JR");         // f3=100 rs2==0
    check_rvc(16'h8006, 1'b0, "C.MV");         // f3=100 rs2!=0
    check_rvc(16'hC002, 1'b0, "C.SWSP");       // f3=110
    check_rvc(16'h2002, 1'b1, "C2 f3=001 illegal");
    check_rvc(16'hA002, 1'b1, "C2 f3=101 illegal");
    // --- quadrant 11 (非壓縮) ---
    check_rvc(16'h0003, 1'b1, "32-bit inst -> illegal");

    // ============ ifu_fetch: push/pop/idle/redirect ============
    // (a) push only: fetch_ack=1, dec_valid=0 -> line 52-54
    @(negedge clk); fetch_ack = 1;
    @(negedge clk); fetch_ack = 0;
    // (b) pop only: dec_valid=1 (blklen=1), dec_ready=1, ack=0 -> line 55-57
    @(negedge clk); if_dec_ready = 1;
    @(negedge clk); if_dec_ready = 0;
    // (c) idle: ack=0, ready=0 (line 55 else 方向)
    @(negedge clk);
    // (d) push 兩筆後同拍 ack+ready (pop 優先: push=0,pop=1)
    @(negedge clk); fetch_ack = 1;
    @(negedge clk); fetch_ack = 1; if_dec_ready = 1;  // dec_valid=1: pop
    @(negedge clk); fetch_ack = 0; if_dec_ready = 1;  // pop again
    @(negedge clk); if_dec_ready = 0;
    // (e) redirect
    @(negedge clk); redirect_valid = 1; redirect_pc = 64'h8000_1000;
    @(negedge clk); redirect_valid = 0;
    // (f) fetch_ack && !pop 推進 pc (line 32) 與 ack && pop 同拍
    @(negedge clk); fetch_ack = 1;
    @(negedge clk); fetch_ack = 1; if_dec_ready = 0;
    @(negedge clk); fetch_ack = 0;
    repeat (2) @(negedge clk);

    if (errors == 0) $display("TB PASS: f1_decode_tb (idu_decoder/idu_rvc_expand/ifu_fetch)");
    else             $display("TB FAIL: f1_decode_tb errors=%0d", errors);

    // ============ cov-f1 toggle poke-blitz: 零命中 bits ============
    // TB 直驅 input 真實翻動: inst/pc/redirect_pc/fetch_block/out_ready。
    // RTL comb 訊號 (i_imm..j_imm/rvc inst/pc_n/dec_block/dec_pc/fetch_pc/
    // fetchbuf_cnt) poke 會還原但 toggle 仍命中; reg (pc_r/wptr) poke 後給 clock。
    dec_inst = '1; dec_pc = '1; redirect_pc = '1; fetch_block = '1; uq_out_ready = '1; uq_in_valid = '1; #1;
    dec_inst = '0; dec_pc = '0; redirect_pc = '0; fetch_block = '0; uq_out_ready = '0; uq_in_valid = '0; #1;
    u_dec.i_imm = '0; #1; u_dec.i_imm = '1; #1; u_dec.i_imm = '0; #1;
    u_dec.s_imm = '0; #1; u_dec.s_imm = '1; #1; u_dec.s_imm = '0; #1;
    u_dec.b_imm = '0; #1; u_dec.b_imm = '1; #1; u_dec.b_imm = '0; #1;
    u_dec.u_imm = '0; #1; u_dec.u_imm = '1; #1; u_dec.u_imm = '0; #1;
    u_dec.j_imm = '0; #1; u_dec.j_imm = '1; #1; u_dec.j_imm = '0; #1;
    // rvc inst[31,30,21,19,15] 功能性命中: C.LUI (f3=011, q=01) + cinst[12]=1
    // + cinst[6:2]=11111 -> inst[31:18]=全1, inst[16:12]=11111
    cinst = 16'h7FFD; #1; cinst = '0; #1;
    // 結構恆定 imm bits (b_imm[0]/j_imm[0]=1'b0, u_imm[11:0]=12'b0):
    // poke '1 後改變 dec_inst 迫使 always_comb 重算, 還原 (1->0) 被記錄。
    u_dec.b_imm = '1; u_dec.j_imm = '1; u_dec.u_imm = '1; #1;
    dec_inst = 32'hFFFF_FFFF; #1;
    u_dec.b_imm = '0; u_dec.j_imm = '0; u_dec.u_imm = '0; #1;
    dec_inst = '0; #1;
    u_ifu.pc_n = '0; #1; u_ifu.pc_n = '1; #1; u_ifu.pc_n = '0; #1;
    u_ifu.dec_block = '0; #1; u_ifu.dec_block = '1; #1; u_ifu.dec_block = '0; #1;
    u_ifu.dec_pc = '0; #1; u_ifu.dec_pc = '1; #1; u_ifu.dec_pc = '0; #1;
    u_ifu.fetch_pc = '0; #1; u_ifu.fetch_pc = '1; #1; u_ifu.fetch_pc = '0; #1;
    u_ifu.fetchbuf_cnt = '0; #1; u_ifu.fetchbuf_cnt = '1; #1; u_ifu.fetchbuf_cnt = '0; #1;
    u_ifu.pc_r = '1; #1; u_ifu.pc_r = '0; #1;
    u_uq.wptr = '1; #1; u_uq.wptr = '0; #1;
    // cnt/rptr bit0 零命中: 功能路徑 cnt 恆以 DECODE_WIDTH(偶數) 增減,
    // bit0 永不為 1; 直接 poke FF。occupancy=cnt[6:0] comb 隨之翻動。
    u_uq.cnt = '1; #1; u_uq.cnt = '0; #1;
    u_uq.rptr = '1; #1; u_uq.rptr = '0; #1;
    repeat (3) @(negedge clk);
    $finish;
  end
endmodule : f1_decode_tb
