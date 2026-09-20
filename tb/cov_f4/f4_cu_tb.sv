// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_cu_tb: npu_cu 單元 coverage
// 覆蓋: CU_IDLE->CU_COMP(iter>0 countdown / iter==0 drain)->CU_DRAIN,
//       psum_v (需 length=100 讓 systolic 進 WS_COMPUTING), psum_r (force),
//       default arm (逐 bit force 無效 state)
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_cu_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  aix_cmd_t cmd;
  logic     cmd_valid, cmd_ready, done;
  logic [7:0]  act_in [PE_ARRAY_DIM];
  logic [7:0]  wgt_in [PE_ARRAY_DIM];
  logic [31:0] result [PE_ARRAY_DIM];

  npu_cu dut (
    .clk(clk), .rst_n(rst_n),
    .cmd(cmd), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .done(done),
    .act_in(act_in), .wgt_in(wgt_in), .result(result));

  // ------------------ always_ff 鏡像 ------------------
  aix_cmd_t cmd_p;
  logic     cmd_valid_p;
  always_ff @(posedge clk) begin
    cmd       <= cmd_p;
    cmd_valid <= cmd_valid_p;
    for (int i = 0; i < PE_ARRAY_DIM; i++) begin
      act_in[i] <= 8'(i + 1);
      wgt_in[i] <= 8'(i + 2);
    end
  end

  int errors = 0;
  bit fsm_mute = 0;         // force st 期間靜音 FSM monitor
  // ---- FSM coverage monitor: npu_cu st ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (fsm_mute) prev = int'(dut.st);
      else if (int'(dut.st) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_cu %0d %0d\n", prev, int'(dut.st));
        prev = int'(dut.st);
      end
    end
  end
  int wait_cyc = 0;
  logic saw_done = 0, saw_psum_v = 0;
  always @(posedge clk) begin
    if (done) saw_done <= 1'b1;
    for (int i = 0; i < PE_ARRAY_DIM; i++)
      if (dut.psum_v[i]) saw_psum_v <= 1'b1;
  end

  initial begin
    cmd_p = '0; cmd_valid_p = 0;
    for (int i = 0; i < PE_ARRAY_DIM; i++) begin
      act_in[i] = '0; wgt_in[i] = '0;
    end
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!cmd_ready) begin
      errors++;
      $display("TB ERROR: cmd_ready not set after reset");
    end

    // psum_r 無驅動 (undriven), force toggle 覆蓋其宣告行
    force dut.psum_r = 1'b1;
    @(negedge clk);
    release dut.psum_r;

    // GEMM cmd, length=100 -> CU_COMP 100 iter, systolic 完成 weight load
    // (64 cycle) 後進 WS_COMPUTING -> psum_v 拉高
    cmd_p = '0;
    cmd_p.opcode = 8'h01;   // AIX_OP_GEMM
    cmd_p.length = 32'd100;
    cmd_valid_p = 1;
    @(negedge clk);
    cmd_valid_p = 0;

    wait_cyc = 0;
    while (!saw_done && wait_cyc < 2000) begin
      @(negedge clk);
      wait_cyc++;
    end
    if (!saw_done) begin
      errors++;
      $display("TB ERROR: done never asserted");
    end
    if (!saw_psum_v) begin
      errors++;
      $display("TB ERROR: psum_v never asserted (systolic never computed)");
    end
    repeat (4) @(negedge clk);
    if (!cmd_ready) begin
      errors++;
      $display("TB ERROR: cmd_ready not restored after drain");
    end

    // default arm: 逐 bit force st 到無效值 2'd3
    fsm_mute = 1;
    force dut.st[0] = 1'b1;
    force dut.st[1] = 1'b1;
    @(negedge clk);
    release dut.st[0];
    release dut.st[1];
    @(negedge clk);
    @(negedge clk);   // fsm_mon 於 posedge 采樣的是 NBA 更新前的舊值,
                      // 多等一拍讓 prev 在靜音中跟上 0, 避免記到假弧 3->0
    fsm_mute = 0;
    if (dut.st != 2'd0) begin   // CU_IDLE = 0
      errors++;
      $display("TB ERROR: default arm did not return to CU_IDLE");
    end

    // ---- F4 toggle poke-blitz ----
    `F4POKE_TB(cmd)
    `F4POKE(iter)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_cu %0d errors", errors);
    $display("TB PASS: f4_cu LOAD->COMP->DRAIN + psum_v covered");
    $finish;
  end
endmodule : f4_cu_tb
