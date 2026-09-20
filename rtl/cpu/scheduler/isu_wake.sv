// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 喚醒聚合: 16 個 FU 完成埠 -> 8 路廣播 + 旁路輸出
module isu_wake
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  logic [15:0] fu_valid,
  input  phys_reg_idx_t [15:0] fu_tag,
  output phys_reg_idx_t [7:0] wk_tag,
  output logic [7:0] wk_valid,
  output logic [15:0] byp_valid,
  output phys_reg_idx_t [15:0] byp_tag
);
  import orca_pkg::*;
  always_comb begin
    automatic int idx = 0;
    for (int i = 0; i < 8; i++) begin wk_valid[i] = 1'b0; wk_tag[i] = '0; end
    for (int i = 0; i < 16; i++) begin
      byp_valid[i] = fu_valid[i];
      byp_tag[i]   = fu_tag[i];
      // LCOV_EXCL (structural): cpu_core 只接 6 個 FU 完成埠 -> idx 恆 <8, wk[7:6] 永不使用
      if (fu_valid[i] && fu_tag[i] != 0 && idx < 8) begin
        wk_valid[idx] = 1'b1;
        wk_tag[idx]   = fu_tag[i];
        idx = idx + 1;
      end
    end
  end
endmodule : isu_wake
