// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 UVM Testbench Top
// File: tb/cpu_tile_tb/tb_uvm_top.sv
// Description: VCS/Xcelium 用 UVM top (本機 Verilator 無 UVM, 不參與本機建置)
//   用法: vcs ... -top tb_uvm_top
//         ./simv +UVM_TESTNAME=orca_cpu_flush_test
//   測試列表見 scripts/run_regression.sh 的 TESTS 陣列
//=============================================================================

`ifndef TB_UVM_TOP_SV
`define TB_UVM_TOP_SV

`include "orca_pkg.sv"

module tb_uvm_top;
  import uvm_pkg::*;
  import orca_uvm_pkg::*;

  logic clk = 0;
  always #5 clk = ~clk;

  // CPU tile 介面 (driver/monitor/coverage 共用)
  orca_cpu_if cpu_if (.clk(clk));

  // TODO(VCS 整合): 於此例化 DUT (orca_v63_cpu_core 或 cpu_tile 層級 wrapper)
  // 並將 cpu_if 各訊號接到 DUT 針腳 / hierarchical 觀察點:
  //   cpu_if.retire_valid/retire_pc/... <- retire 匯流排
  //   cpu_if.flush_valid                <- cmt_rob.flush_pipeline
  //   cpu_if.lsu_lane_valid             <- isu_mem issue valid (4 lane)
  //   cpu_if.prf_wvalid                 <- PRF 12 寫埠 valid

  initial begin
    uvm_config_db#(virtual orca_cpu_if)::set(null, "uvm_test_top", "vif", cpu_if);
    run_test();   // 由 +UVM_TESTNAME=<test> 選擇 test class
  end

  // 波形 (VCS)
  initial begin
`ifdef VCS
    $vcdpluson;
`endif
  end
endmodule : tb_uvm_top

`endif // TB_UVM_TOP_SV
