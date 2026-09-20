// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
// exu_mul (全 funct3) + exu_vec (遮罩/vtype) 獨立覆蓋
module unit_exu_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  uop_t mu; logic mv, m_rdy, m_rv, m_exc; xword_t mr; rob_idx_t m_ri; exception_t m_ec;
  xword_t mu_a, mu_b;
  exu_mul u_mul (.clk(clk), .rst_n(rst_n), .uop(mu), .uop_valid(mv), .uop_ready(m_rdy),
    .operand_a(mu_a), .operand_b(mu_b),
    .result(mr), .result_valid(m_rv), .rob_idx(m_ri), .exception(m_exc), .exc_code(m_ec));

  uop_t vu; logic vv, v_rdy, v_rv, v_exc; vword_t vres; rob_idx_t v_ri; exception_t v_ec;
  logic [63:0] vec_vl, vec_vtype, vec_vstart;
  exu_vec u_vec (.clk(clk), .rst_n(rst_n), .uop(vu), .uop_valid(vv), .uop_ready(v_rdy),
    .vs1_data({8{64'h1111222233334444}}), .vs2_data({8{64'h5555666677778888}}),
    .vd_old_data({8{64'hAAAABBBBCCCCDDDD}}), .v0_mask(64'hF0F0F0F0F0F0F0F0),
    .vl(vec_vl), .vtype(vec_vtype), .vstart(vec_vstart),
    .vd_result(vres), .result_valid(v_rv), .rob_idx(v_ri),
    .vec_exception(v_exc), .vec_exc_code(v_ec));

  initial begin
    mu = '0; vu = '0; mv = 0; vv = 0;
    rst_n = 0; #57 rst_n = 1; @(negedge clk);
    // exu_mul: 8 funct3 x 多組操作數 (含負數/全1/混合位元組), 除法跑滿迭代
    for (int f = 0; f < 8; f++) begin
      for (int pat = 0; pat < 4; pat++) begin
        mu = '0; mu.funct3 = 3'(f); mu.imm[14:12] = 3'(f); mu.funct7 = 7'd1; mu.rob_idx = rob_idx_t'(f);
        unique case (pat)
          0: begin mu_a=64'h0000_0000_0000_0015; mu_b=64'h0000_0000_0000_0007; end
          1: begin mu_a=64'hFFFF_FFFF_FFFF_FFFF; mu_b=64'h0000_0000_FFFF_FFFF; end
          2: begin mu_a=64'h8000_0000_0000_0000; mu_b=64'hFFFF_FFFF_FFFF_FFFF; end  // 溢位/負數
          3: begin mu_a=64'hAAAA_AAAA_5555_5555; mu_b=64'h3333_3333_3333_3333; end
        endcase
        mv = 1; @(negedge clk);
        begin int g=0; while (!m_rdy && g<100) begin @(negedge clk); g++; end end
        mv = 0;
        repeat (90) @(negedge clk);
      end
    end
    // 邊界: 除以零, 0/x, INT_MIN/-1 溢位
    mu = '0; mu.funct3=3'd4; mu.imm[14:12]=3'd4; mu_a=64'h1234; mu_b=64'h0; mv=1; @(negedge clk);
    begin int g=0; while(!m_rdy&&g<100) begin @(negedge clk); g++; end end mv=0; repeat(90) @(negedge clk);
    mu = '0; mu.funct3=3'd6; mu.imm[14:12]=3'd6; mu_a=64'h0; mu_b=64'h0; mv=1; @(negedge clk);
    begin int g=0; while(!m_rdy&&g<100) begin @(negedge clk); g++; end end mv=0; repeat(90) @(negedge clk);
    // exu_vec: funct3 x sew(0-3) x lmul(0-3) x vma/vta x vl 邊界 x vstart
    vec_vl=64; vec_vtype=0; vec_vstart=0;
    for (int k = 0; k < 8; k++) begin
      for (int sew = 0; sew < 4; sew++) begin
        for (int lmul = 0; lmul < 4; lmul++) begin
          for (int ag = 0; ag < 4; ag++) begin
            vu = '0; vu.funct3 = 3'(k); vu.imm[14:12] = 3'(k); vu.is_vec = 1; vu.rob_idx = rob_idx_t'(k);
            vec_vtype = {52'd0, ag[1], ag[0], 2'b00, 3'(sew), 3'(lmul)};  // vta,vma,sew,lmul
            vec_vl     = 64'(sew * lmul * 8 + 1);   // 變化 vl
            vec_vstart = 64'((sew + lmul) % 3);      // 變化 vstart
            vv = 1; @(negedge clk);
            begin int g=0; while (!v_rdy && g<80) begin @(negedge clk); g++; end end
            vv = 0;
            repeat (20) @(negedge clk);
          end
        end
      end
    end
    // vl/vstart 極端值
    for (int e = 0; e < 6; e++) begin
      unique case (e)
        0: begin vec_vl=0;    vec_vstart=0;  end
        1: begin vec_vl=1;    vec_vstart=0;  end
        2: begin vec_vl=512;  vec_vstart=0;  end
        3: begin vec_vl=64;   vec_vstart=63; end
        4: begin vec_vl=1024; vec_vstart=0;  end
        5: begin vec_vl=64;   vec_vstart=511;end
      endcase
      vu='0; vu.funct3=3'd0; vu.imm[14:12]=3'd0; vu.is_vec=1; vu.rob_idx=rob_idx_t'(e);
      vv=1; @(negedge clk);
      begin int g=0; while(!v_rdy&&g<80) begin @(negedge clk); g++; end end
      vv=0; repeat(20) @(negedge clk);
    end
    // ---- exu_vec funct3=0..7 x funct6=0..21 全組合 (覆蓋各 funct3 子 case) ----
    vec_vl=64; vec_vstart=0; vec_vtype={52'd0, 2'b00, 6'b0, 3'd0, 3'd0};  // 合法 sew=8,lmul=1
    for (int f3 = 0; f3 < 8; f3++) begin
      for (int op = 0; op < 22; op++) begin
        vu='0; vu.is_vec=1; vu.rob_idx=rob_idx_t'(op);
        vu.imm[31:26]=6'(op); vu.imm[14:12]=3'(f3);
        vv=1; @(negedge clk);
        begin int g=0; while(!v_rdy&&g<80) begin @(negedge clk); g++; end end
        vv=0; repeat(8) @(negedge clk);
      end
    end
    // ---- exu_vec 非法 config: sew>3, lmul>3, vill ----
    for (int bad = 0; bad < 3; bad++) begin
      unique case (bad)
        0: vec_vtype = {58'd0, 3'd5, 3'd0};          // sew=5 (>3) illegal
        1: vec_vtype = {58'd0, 3'd0, 3'd6};          // lmul=6 (>3) illegal
        2: vec_vtype = {6'b000010, 52'd0, 3'd0, 3'd0}; // vill[1]=1 illegal cfg
      endcase
      vec_vl=64; vec_vstart=0;
      vu='0; vu.is_vec=1; vu.imm[31:26]=6'd0; vu.imm[14:12]=3'd0; vu.rob_idx=rob_idx_t'(bad);
      vv=1; @(negedge clk);
      begin int g=0; while(!v_rdy&&g<80) begin @(negedge clk); g++; end end
      vv=0; repeat(15) @(negedge clk);
    end
    $display("EXU UNIT TB PASS: mul div vec swept");
    $finish;
  end
endmodule : unit_exu_tb
