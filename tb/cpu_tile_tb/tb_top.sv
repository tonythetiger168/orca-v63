// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"

// CPU core smoke test: reset -> 取指 -> L2 fetch 活動檢查
module tb_top;
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

  int fill_cnt = 0;
  always_ff @(posedge clk) begin
    l2f <= 1'b0;
    if (l2v) begin
      l2l   <= {8{64'h0000_0013_0000_0113}};   // nop stream
      l2f   <= 1'b1;
      fill_cnt <= fill_cnt + 1;
    end
  end

  initial begin
    tid = 2'b0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (200) @(negedge clk);
    if (fill_cnt == 0) $fatal(1, "TB FAIL: no L2 fetch activity");
    $display("TB PASS: %0d L2 fetches", fill_cnt);
    $finish;
  end
endmodule : tb_top
