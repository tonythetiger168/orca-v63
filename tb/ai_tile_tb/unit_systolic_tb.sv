// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
// npu_systolic 全覆蓋: clk_gate_en/weight ping-pong/activation flow/accumulate/
// flush/sparse/dtype/weight-stationary。小陣列(8x8)加速。
module unit_systolic_tb;
  import orca_pkg::*;
  localparam int AD = 8, DW = 8;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  logic ckg, wl_v, wl_rdy, wl_row, act_v, act_rdy, ps_rdy;
  logic [DW-1:0] wl_data [AD], act_in [AD];
  logic [31:0] ps_out [AD]; logic ps_v [AD];
  logic [3:0] dt; logic wstat, acc_en, flush, sp_mode; logic [AD-1:0] sp_mask;

  npu_systolic #(.ARRAY_DIM(AD), .DATA_WIDTH(DW)) u_sa (
    .clk(clk), .rst_n(rst_n), .clk_gate_en(ckg),
    .weight_load_data(wl_data), .weight_load_valid(wl_v), .weight_load_ready(wl_rdy),
    .weight_load_row(wl_row),
    .activation_in(act_in), .activation_valid(act_v), .activation_ready(act_rdy),
    .partial_sum_out(ps_out), .partial_sum_valid(ps_v), .partial_sum_ready(ps_rdy),
    .dtype(dt), .weight_stationary(wstat), .accumulate_en(acc_en),
    .flush_acc(flush), .sparse_mode(sp_mode), .sparse_mask(sp_mask));

  task automatic ld_w(input int row);
    for (int i=0;i<AD;i++) wl_data[i]=8'(i*3+row+1);
    wl_row=row; wl_v=1;
    @(negedge clk);
    begin int g=0; while(!wl_rdy && g<40) begin @(negedge clk); g++; end end
    wl_v=0; @(negedge clk);
  endtask

  initial begin
    ckg=0; wl_v=0; wl_row=0; act_v=0; ps_rdy=0; dt=0; wstat=1; acc_en=0; flush=0; sp_mode=0; sp_mask='1;
    for(int i=0;i<AD;i++) begin wl_data[i]=8'h0; act_in[i]=8'h0; end
    rst_n=0; #57 rst_n=1; @(negedge clk);

    // clk_gate_en 開關 (低功耗路徑)
    ckg=0; repeat(10) @(negedge clk);
    ckg=1; repeat(10) @(negedge clk);

    // weight ping-pong 載入 (row 0 和 row 1)
    ld_w(0); ld_w(1);

    // 各 dtype 計算 (weight-stationary)
    for (int d=0; d<10; d++) begin
      dt=4'(d); wstat=1; acc_en=1; flush=(d==0); ps_rdy=1; sp_mode=0;
      for (int i=0;i<AD;i++) act_in[i]=8'(i+1);
      act_v=1; @(negedge clk);
      begin int g=0; while(!act_rdy && g<40) begin @(negedge clk); g++; end end
      act_v=0; repeat(20) @(negedge clk);
    end

    // flow-through (weight_stationary=0)
    wstat=0; acc_en=1;
    for (int i=0;i<AD;i++) act_in[i]=8'h55;
    act_v=1; @(negedge clk);
    begin int g=0; while(!act_rdy && g<40) begin @(negedge clk); g++; end end
    act_v=0; repeat(20) @(negedge clk);

    // sparse_mode + mask 變體
    sp_mode=1;
    for (int m=0; m<4; m++) begin
      sp_mask = AD'(m==0 ? 8'hFF : m==1 ? 8'h0F : m==2 ? 8'hF0 : 8'hAA);
      acc_en=1; wstat=1; ps_rdy=1;
      for (int i=0;i<AD;i++) act_in[i]=8'(m+i);
      act_v=1; @(negedge clk);
      begin int g=0; while(!act_rdy && g<40) begin @(negedge clk); g++; end end
      act_v=0; repeat(20) @(negedge clk);
    end
    sp_mode=0;

    // flush + accumulate 交錯
    for (int k=0; k<4; k++) begin
      acc_en=(k%2==0); flush=(k%2==1); ps_rdy=1;
      for (int i=0;i<AD;i++) act_in[i]=8'(k*10+i);
      act_v=1; @(negedge clk);
      begin int g=0; while(!act_rdy && g<40) begin @(negedge clk); g++; end end
      act_v=0; repeat(15) @(negedge clk);
    end
    // ps_rdy=0 (背壓)
    ps_rdy=0; acc_en=1; act_v=1; @(negedge clk);
    begin int g=0; while(!act_rdy && g<40) begin @(negedge clk); g++; end end
    act_v=0; repeat(20) @(negedge clk);

    $display("SYSTOLIC TB PASS");
    $finish;
  end
endmodule : unit_systolic_tb
