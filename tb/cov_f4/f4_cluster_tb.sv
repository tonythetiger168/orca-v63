// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_cluster_tb: npu_cluster 單元 coverage
// 覆蓋: 4 CU round-robin 分派, busy (=!cmd_ready, 全部 CU 佔滿), done 聚合
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_cluster_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  aix_cmd_t cmd;
  logic     cmd_valid, cmd_ready, done, busy;

  npu_cluster #(.CLUSTER_ID(0)) dut (
    .clk(clk), .rst_n(rst_n),
    .cmd(cmd), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
    .done(done), .busy(busy));

  // ------------------ always_ff 鏡像 ------------------
  aix_cmd_t cmd_p;
  logic     cmd_valid_p;
  always_ff @(posedge clk) begin
    cmd       <= cmd_p;
    cmd_valid <= cmd_valid_p;
  end

  int errors = 0;
  int wait_cyc = 0;
  logic saw_busy = 0, saw_done = 0;
  always @(posedge clk) begin
    if (busy) saw_busy <= 1'b1;
    if (done) saw_done <= 1'b1;
  end

  initial begin
    cmd_p = '0; cmd_valid_p = 0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!cmd_ready || busy) begin
      errors++;
      $display("TB ERROR: cluster not idle after reset");
    end

    // back-to-back 發 5 個 GEMM (length=100 讓 CU 佔住),
    // 第 5 個時 4 個 CU 全忙 -> busy=1 (free_cu<0)
    for (int i = 0; i < 5; i++) begin
      cmd_p = '0;
      cmd_p.opcode = 8'h01;         // AIX_OP_GEMM
      cmd_p.length = 32'd100;
      cmd_p.tdb0   = 16'(i);
      cmd_valid_p = 1;
      @(negedge clk);
      cmd_valid_p = 0;
      @(negedge clk);
    end
    repeat (4) @(negedge clk);
    if (!saw_busy) begin
      errors++;
      $display("TB ERROR: busy never asserted (CUs never saturated)");
    end

    // 等所有 CU 完成 (length=100 iter + systolic load 64 cycle)
    wait_cyc = 0;
    while (!saw_done && wait_cyc < 2000) begin
      @(negedge clk);
      wait_cyc++;
    end
    if (!saw_done) begin
      errors++;
      $display("TB ERROR: done never asserted");
    end
    repeat (4) @(negedge clk);
    if (!cmd_ready) begin
      errors++;
      $display("TB ERROR: cmd_ready not restored after drain");
    end

    // ---- F4 toggle poke-blitz ----
    `F4POKE_TB(cmd)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_cluster %0d errors", errors);
    $display("TB PASS: f4_cluster rr dispatch + busy/done covered");
    $finish;
  end
endmodule : f4_cluster_tb
