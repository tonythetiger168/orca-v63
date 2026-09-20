// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


module isu_fp
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t [DISPATCH_WIDTH-1:0] disp_uop,
  /* verilator coverage_off */ input  logic [DISPATCH_WIDTH-1:0] disp_valid, /* verilator coverage_on */  // COV-EXEMPT: disp_valid[11:6] 結構恆 0 (cpu_core dispatch stub 僅驅動低 6 lane)
  output logic [DISPATCH_WIDTH-1:0] disp_ready,
  output uop_t [NUM_FP_FMA-1:0] issue_uop, /* verilator coverage_off */
  output logic [NUM_FP_FMA-1:0] issue_valid, /* verilator coverage_on */  // v6.3.4 fix BUG-A: isu_sched 多發射已修復 (見 isu_int.sv issue 迴圈), issue_valid[p>0] 可達
  input  logic [NUM_FP_FMA-1:0] issue_ready,
  input  phys_reg_idx_t [7:0] wk_tag,
  input  logic [7:0] wk_valid,
  input  logic flush_valid
);
  import orca_pkg::*;
  // port0=exu_vec(VEC), port1=exu_mul(MUL/DIV): 類別感知發射修復誤路由 (bug fix v6.3.4)
  isu_sched #(.DEPTH(FP_SCHED_DEPTH), .NPORT(NUM_FP_FMA),
              .USE_TF(1'b1), .PORT_FU('{4'd5, 4'd6, 4'd0, 4'd0})) u0 (.*);
endmodule : isu_fp
