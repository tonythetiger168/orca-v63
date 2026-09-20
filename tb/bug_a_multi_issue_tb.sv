// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.4 BUG-A directed test: isu_sched 多發射仲裁
// 證明同拍 >=2 個就緒 uop 時 issue_valid[0] 與 issue_valid[1] 同拍為 1,
// 且各 port 依 uop_id oldest-first 發射 (port p 取第 p+1 老)。
`include "orca_pkg.sv"

module bug_a_multi_issue_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  int errors = 0;

  uop_t [DISPATCH_WIDTH-1:0] s_uop;
  logic [DISPATCH_WIDTH-1:0] s_valid, s_ready;
  uop_t [NUM_INT_ALU-1:0] i_uop;
  logic [NUM_INT_ALU-1:0] i_valid, i_ready;
  phys_reg_idx_t [7:0] wk_tag;
  logic [7:0] wk_valid;
  logic flush_sched;

  isu_int u_isu (
    .clk(clk), .rst_n(rst_n),
    .disp_uop(s_uop), .disp_valid(s_valid), .disp_ready(s_ready),
    .issue_uop(i_uop), .issue_valid(i_valid), .issue_ready(i_ready),
    .wk_tag(wk_tag), .wk_valid(wk_valid), .flush_valid(flush_sched));

  function automatic uop_t mk(input int uid);
    uop_t u;
    u = `UOP_NOP;
    u.opcode = OP_ALU;
    u.rd = 5'd1;  u.rs1 = 5'd0;  u.rs2 = 5'd0;   // rs=0 → 立即就緒
    u.uop_id = 16'(uid);
    u.pc = 64'(uid * 4);
    return u;
  endfunction

  initial begin
    $display("BUG_A_MULTI_ISSUE BOOT");
    s_valid = '0;  i_ready = '0;  wk_valid = '0;
    for (int i = 0; i < 8; i++) wk_tag[i] = phys_reg_idx_t'(0);
    flush_sched = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // 囤積 4 筆就緒 uop (RTL insert 每拍僅插 1 筆, 逐拍送 slot0)
    for (int c = 0; c < 4; c++) begin
      s_valid[0] = 1;
      s_uop[0] = mk(7000 + c);
      @(posedge clk); #1;
    end
    s_valid = '0;
    @(negedge clk);

    // 放開 issue_ready: 4 筆同就緒 → 4 port 應同拍發射
    i_ready = '1;
    #1;
    $display("  issue_valid=%0b uop_id: p0=%0d p1=%0d p2=%0d p3=%0d",
             i_valid, i_uop[0].uop_id, i_uop[1].uop_id,
             i_uop[2].uop_id, i_uop[3].uop_id);
    // 主要檢查: issue_valid[0] 與 issue_valid[1] 同拍為 1
    if (!(i_valid[0] && i_valid[1])) begin
      errors++; $display("ERR: issue_valid[0] & issue_valid[1] not both 1 (iv=%0b)", i_valid);
    end
    // 全 4 port 應同時發射 (4 筆就緒)
    if (i_valid !== 4'b1111) begin
      errors++; $display("ERR: expected issue_valid=1111, got %0b", i_valid);
    end
    // oldest-first: p0<p1<p2<p3 uop_id 遞增且為 7000..7003
    for (int p = 0; p < NUM_INT_ALU; p++)
      if (i_uop[p].uop_id !== 16'(7000 + p)) begin
        errors++; $display("ERR: port %0d uop_id=%0d, expected %0d",
                           p, i_uop[p].uop_id, 7000 + p);
      end

    // 下一拍: 全數被取走, issue_valid 應歸零
    @(posedge clk); #1;
    if (i_valid !== 4'b0000) begin
      errors++; $display("ERR: entries not drained after issue, iv=%0b", i_valid);
    end

    // 第二輪: 僅 2 筆就緒 → issue_valid[1:0]=11, [3:2]=00
    @(negedge clk);
    i_ready = '0;
    for (int c = 0; c < 2; c++) begin
      s_valid[0] = 1;
      s_uop[0] = mk(7100 + c);
      @(posedge clk); #1;
    end
    s_valid = '0;
    @(negedge clk);
    i_ready = '1;
    #1;
    $display("  round2 issue_valid=%0b p0_id=%0d p1_id=%0d",
             i_valid, i_uop[0].uop_id, i_uop[1].uop_id);
    if (i_valid !== 4'b0011) begin
      errors++; $display("ERR: round2 expected issue_valid=0011, got %0b", i_valid);
    end
    if (i_uop[0].uop_id !== 16'd7100 || i_uop[1].uop_id !== 16'd7101) begin
      errors++; $display("ERR: round2 oldest-first order wrong");
    end
    @(posedge clk); #1;

    repeat (2) @(negedge clk);
    if (errors == 0) $display("BUG_A_MULTI_ISSUE_TB PASS");
    else             $display("BUG_A_MULTI_ISSUE_TB FAIL errors=%0d", errors);
    $finish;
  end
endmodule : bug_a_multi_issue_tb
