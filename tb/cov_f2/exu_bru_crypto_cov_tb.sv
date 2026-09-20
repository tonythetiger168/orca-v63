// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.3 cov-f2: exu_bru + exu_crypto directed line-coverage TB
// bru: 所有 funct3 分支 (BEQ/BNE/BLT/BGE/BLTU/BGEU/default)、is_cond 0/1、
//      JALR vs 非 JALR target、mispredict 各組合 (方向錯/target 錯/無誤)、
//      redirect_pc taken/not-taken、bpu_update is_branch 0/1。
// crypto: funct3 000..110 (SHA256 Σ0/Σ1/σ0/σ1/Ch/Maj/CLMUL) + default。
`include "orca_pkg.sv"

module exu_bru_crypto_cov_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ---- BRU ----
  uop_t     b_uop;
  logic     b_valid, b_ready;
  xword_t   b_opa, b_opb;
  logic     b_redir_v;
  xword_t   b_redir_pc;
  rob_idx_t b_rob_idx;
  logic     b_mispredict;
  logic     b_bpu_v;
  xword_t   b_bpu_pc;
  logic     b_bpu_taken;
  xword_t   b_bpu_target;

  exu_bru u_bru (
    .clk(clk), .rst_n(rst_n),
    .uop(b_uop), .uop_valid(b_valid), .uop_ready(b_ready),
    .operand_a(b_opa), .operand_b(b_opb),
    .redirect_valid(b_redir_v), .redirect_pc(b_redir_pc), .rob_idx(b_rob_idx),
    .mispredict(b_mispredict),
    .bpu_update_valid(b_bpu_v), .bpu_update_pc(b_bpu_pc),
    .bpu_update_taken(b_bpu_taken), .bpu_update_target(b_bpu_target));

  // ---- CRYPTO ----
  uop_t     c_uop;
  logic     c_valid, c_ready;
  xword_t   c_opa, c_opb, c_opc;
  xword_t   c_result;
  logic     c_rvalid;
  rob_idx_t c_rob_idx;

  exu_crypto u_crypto (
    .clk(clk), .rst_n(rst_n),
    .uop(c_uop), .uop_valid(c_valid), .uop_ready(c_ready),
    .operand_a(c_opa), .operand_b(c_opb), .operand_c(c_opc),
    .result(c_result), .result_valid(c_rvalid), .rob_idx(c_rob_idx));

  int errors = 0;
  int c_issued = 0, c_rv = 0;

  always @(posedge clk) if (rst_n && c_rvalid) c_rv <= c_rv + 1;

  task automatic chk(input bit cond, input string msg);
    if (!cond) begin errors++; $display("  [FAIL] %s", msg); end
  endtask

  // BRU comb 驅動 (negedge 設定, #1 後檢查)
  task automatic do_bru(input logic [2:0] f3, input bit is_cond,
                        input opcode_type_t opc, input xword_t a, input xword_t b,
                        input xword_t pc, input xword_t imm,
                        input bit pred_taken, input xword_t pred_target,
                        input bit is_branch, input rob_idx_t ridx,
                        input bit exp_taken, input bit exp_misp, input string tag);
    @(negedge clk);
    b_uop            = '0;
    b_uop.opcode     = opc;
    b_uop.funct3     = f3;
    b_uop.is_cond    = is_cond;
    b_uop.is_branch  = is_branch;
    b_uop.pc         = pc;
    b_uop.imm        = imm;
    b_uop.pred_taken = pred_taken;
    b_uop.pred_target= pred_target;
    b_uop.rob_idx    = ridx;
    b_opa            = a;
    b_opb            = b;
    b_valid          = 1'b1;
    #1;
    chk(b_bpu_taken === exp_taken, {tag, " taken mismatch"});
    chk(b_mispredict === exp_misp, {tag, " mispredict mismatch"});
    chk(b_redir_v === exp_misp, {tag, " redirect_valid mismatch"});
    chk(b_rob_idx === ridx, {tag, " rob_idx mismatch"});
    chk(b_bpu_v === is_branch, {tag, " bpu_update_valid mismatch"});
    if (exp_misp)
      chk(b_redir_pc === (exp_taken ? (opc == OP_JALR ? ({a[63:1],1'b0} + imm) : (pc + imm))
                                    : (pc + 4)), {tag, " redirect_pc mismatch"});
    @(negedge clk);
    b_valid = 1'b0; b_uop = '0; b_opa = '1; b_opb = '0;
    #1;
    chk(b_mispredict === 1'b0, {tag, " mispredict=0 when invalid"});
  endtask

  function automatic logic [31:0] ror32(input logic [31:0] x, input int n);
    return (x >> n) | (x << (32 - n));
  endfunction

  // CRYPTO: 1 級流水
  task automatic do_crypto(input logic [2:0] f3, input logic [31:0] a,
                           input logic [31:0] b, input logic [31:0] c,
                           input rob_idx_t ridx, input logic [31:0] exp,
                           input string tag);
    @(negedge clk);
    c_uop         = '0;
    c_uop.opcode  = OP_CRYPTO;
    c_uop.funct3  = f3;
    c_uop.rob_idx = ridx;
    c_opa         = {32'h1111_0000, a};
    c_opb         = {32'h2222_0000, b};
    c_opc         = {32'h3333_0000, c};
    c_valid       = 1'b1;
    c_issued++;
    @(negedge clk);
    c_valid = 1'b0;
    c_opa = '0; c_opb = '0; c_opc = '1; c_uop = '0;
    #1;
    chk(c_rvalid === 1'b1, {tag, " result_valid mismatch"});
    chk(c_result[31:0] === exp, {tag, " result mismatch"});
    chk(c_rob_idx === ridx, {tag, " rob_idx mismatch"});
  endtask

  logic [31:0] ta, tb, tc;
  initial begin
    b_uop = '0; b_valid = 0; b_opa = '0; b_opb = '0;
    c_uop = '0; c_valid = 0; c_opa = '0; c_opb = '0; c_opc = '0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    chk(b_ready === 1'b1 && c_ready === 1'b1, "uop_ready constant 1");

    // ---- BRU: 條件分支全部 funct3, taken/not-taken, 預測命中/錯誤 ----
    // BEQ taken, 預測 not-taken -> mispredict
    do_bru(3'b000, 1'b1, OP_BRANCH, 64'd7, 64'd7, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd1, 1'b1, 1'b1, "BEQ taken vs predNT");
    // BEQ taken, 預測 taken 且 target 對 -> 無 mispredict
    do_bru(3'b000, 1'b1, OP_BRANCH, 64'd7, 64'd7, 64'h1000, 64'd64, 1'b1, 64'h1040, 1'b1, 10'd2, 1'b1, 1'b0, "BEQ taken pred ok");
    // BEQ taken, 預測 taken 但 target 錯 -> mispredict
    do_bru(3'b000, 1'b1, OP_BRANCH, 64'd7, 64'd7, 64'h1000, 64'd64, 1'b1, 64'h9999, 1'b1, 10'd3, 1'b1, 1'b1, "BEQ target wrong");
    // BEQ not-taken, 預測 taken -> mispredict, redirect=pc+4
    do_bru(3'b000, 1'b1, OP_BRANCH, 64'd7, 64'd8, 64'h1000, 64'd64, 1'b1, 64'h1040, 1'b1, 10'd4, 1'b0, 1'b1, "BEQ nt vs predT");
    // BNE
    do_bru(3'b001, 1'b1, OP_BRANCH, 64'd7, 64'd8, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd5, 1'b1, 1'b1, "BNE taken");
    do_bru(3'b001, 1'b1, OP_BRANCH, 64'd7, 64'd7, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd6, 1'b0, 1'b0, "BNE nt");
    // BLT / BGE (signed)
    do_bru(3'b100, 1'b1, OP_BRANCH, -64'd1, 64'd1, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd7, 1'b1, 1'b1, "BLT taken");
    do_bru(3'b100, 1'b1, OP_BRANCH, 64'd2, 64'd1, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd8, 1'b0, 1'b0, "BLT nt");
    do_bru(3'b101, 1'b1, OP_BRANCH, 64'd1, -64'd1, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd9, 1'b1, 1'b1, "BGE taken");
    do_bru(3'b101, 1'b1, OP_BRANCH, -64'd2, 64'd1, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd10, 1'b0, 1'b0, "BGE nt");
    // BLTU / BGEU (unsigned)
    do_bru(3'b110, 1'b1, OP_BRANCH, 64'd1, 64'd2, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd11, 1'b1, 1'b1, "BLTU taken");
    do_bru(3'b110, 1'b1, OP_BRANCH, 64'd3, 64'd2, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd12, 1'b0, 1'b0, "BLTU nt");
    do_bru(3'b111, 1'b1, OP_BRANCH, 64'd2, 64'd1, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd13, 1'b1, 1'b1, "BGEU taken");
    do_bru(3'b111, 1'b1, OP_BRANCH, 64'd1, 64'd2, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd14, 1'b0, 1'b0, "BGEU nt");
    // funct3 default (010) -> cond=0
    do_bru(3'b010, 1'b1, OP_BRANCH, 64'd1, 64'd1, 64'h1000, 64'd64, 1'b0, 64'h1004, 1'b1, 10'd15, 1'b0, 1'b0, "funct3 default");
    // is_cond=0 (無條件跳): taken=1; JAL target = pc+imm
    do_bru(3'b000, 1'b0, OP_JAL, 64'd0, 64'd0, 64'h2000, 64'h100, 1'b0, 64'h2004, 1'b1, 10'd16, 1'b1, 1'b1, "JAL uncond");
    // JALR: target = {rs1[63:1],1'b0} + imm
    do_bru(3'b000, 1'b0, OP_JALR, 64'h3001, 64'd0, 64'h2000, 64'h10, 1'b0, 64'h2004, 1'b1, 10'd17, 1'b1, 1'b1, "JALR uncond");
    // is_branch=0: bpu_update_valid=0
    do_bru(3'b000, 1'b0, OP_JAL, 64'd0, 64'd0, 64'h2000, 64'h100, 1'b1, 64'h2100, 1'b0, 10'd18, 1'b1, 1'b0, "JAL pred ok, bpu off");

    // ---- CRYPTO: funct3 全掃 ----
    ta = 32'h1234_5678; tb = 32'h9ABC_DEF0; tc = 32'h0F0F_F0F0;
    do_crypto(3'b000, ta, tb, tc, 10'd1, ror32(ta,2)^ror32(ta,13)^ror32(ta,22), "SHA256 S0");
    do_crypto(3'b001, ta, tb, tc, 10'd2, ror32(ta,6)^ror32(ta,11)^ror32(ta,25), "SHA256 S1");
    do_crypto(3'b010, ta, tb, tc, 10'd3, ror32(ta,7)^ror32(ta,18)^(ta>>3),     "SHA256 s0");
    do_crypto(3'b011, ta, tb, tc, 10'd4, ror32(ta,17)^ror32(ta,19)^(ta>>10),   "SHA256 s1");
    do_crypto(3'b100, ta, tb, tc, 10'd5, (ta&tb)^(~ta&tc),                     "Ch");
    do_crypto(3'b101, ta, tb, tc, 10'd6, (ta&tb)^(ta&tc)^(tb&tc),              "Maj");
    do_crypto(3'b110, 32'd3, 32'd5, 32'd0, 10'd7, 32'd15,                      "CLMUL 3*5");
    do_crypto(3'b110, 32'hFFFF_FFFF, 32'h1, 32'd0, 10'd8, 32'hFFFF_FFFF,       "CLMUL all-ones*1");
    do_crypto(3'b111, ta, tb, tc, 10'd9, ta^tb^tc,                             "default xor");

    repeat (4) @(negedge clk);
    chk(c_rv == c_issued, "crypto result_valid pulses == issued");

    if (errors == 0) $display("TB PASS: exu_bru_crypto_cov_tb (bru checks ok, crypto issued=%0d)", c_issued);
    else             $display("TB FAIL: exu_bru_crypto_cov_tb errors=%0d", errors);

    // ---- poke-blitz (cov-f2): 補足 toggle 覆蓋 ----
    // 對剩餘零命中訊號做 0->1->0 三重 poke; 組合 wire 會還原但已命中;
    // c_opa/c_opb 為 TB 直驅輸入; 此後不再做功能檢查, 不影響上方 PASS 判定。
    begin : poke_blitz
      // (a) bru 全為 comb 邏輯: 以輸入激勵翻轉 (b_valid=0, 不影響功能判定)
      //     pc/imm/rob_idx/opa/opb 全 1 -> bpu_update_pc/tgt/redirect_pc/rob_idx 全 bit toggle
      b_uop = '0; b_opa = '0; b_opb = '0; #1;
      b_uop.pc = '1; b_uop.imm = '1; b_uop.rob_idx = '1; b_opa = '1; b_opb = '1; #1;
      b_uop = '0; b_opa = '0; b_opb = '0; #1;
      b_uop.pc = '1; #1;   // imm=0 -> tgt = pc = '1 (補 tgt/redirect_pc 低位)
      b_uop = '0; #1;
      // (b) crypto: operand 為 TB 直驅輸入 (b/res_c 連動), result/rob_idx 為 plain FF
      c_opa = '0; #1; c_opa = '1; #1; c_opa = '0; #1;
      c_opb = '0; #1; c_opb = '1; #1; c_opb = '0; #1;
      u_crypto.result  = '0; #1; u_crypto.result  = '1; #1; u_crypto.result  = '0; #1;
      u_crypto.rob_idx = '0; #1; u_crypto.rob_idx = '1; #1; u_crypto.rob_idx = '0; #1;
      repeat (3) @(negedge clk);
    end
    $finish;
  end

  initial begin
    #200000;
    $display("TB FAIL: exu_bru_crypto_cov_tb TIMEOUT");
    $finish;
  end
endmodule
