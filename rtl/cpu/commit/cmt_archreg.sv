// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 架構暫存器檔: 32 int + 32 fp per thread, 16-wide retire 寫, 除錯讀
module cmt_archreg
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  tid_t [RETIRE_WIDTH-1:0] rt_tid,
  input  arch_reg_idx_t [RETIRE_WIDTH-1:0] rt_rda,
  input  phys_reg_idx_t [RETIRE_WIDTH-1:0] rt_prd,
  input  xword_t [RETIRE_WIDTH-1:0] rt_data,
  input  logic [RETIRE_WIDTH-1:0] rt_valid,
  input  logic [RETIRE_WIDTH-1:0] rt_fp,
  output phys_reg_idx_t cur_map [SMT_THREADS][32],
  input  tid_t dbg_tid,
  input  arch_reg_idx_t dbg_rda,
  input  logic dbg_fp,
  output xword_t dbg_rdata
);
  import orca_pkg::*;
  xword_t ireg [SMT_THREADS][32];
  xword_t freg [SMT_THREADS][32];
  always_comb begin
    for (int t = 0; t < SMT_THREADS; t++)
      for (int a = 0; a < 32; a++)
        cur_map[t][a] = phys_reg_idx_t'(a);
    dbg_rdata = dbg_fp ? freg[dbg_tid][dbg_rda] : ireg[dbg_tid][dbg_rda];
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int t = 0; t < SMT_THREADS; t++)
        for (int a = 0; a < 32; a++) begin
          ireg[t][a] <= '0; freg[t][a] <= '0;
        end
    end else begin
      for (int i = 0; i < RETIRE_WIDTH; i++)
        if (rt_valid[i] && rt_rda[i] != 0) begin
          if (rt_fp[i]) freg[rt_tid[i]][rt_rda[i]] <= rt_data[i];
          else          ireg[rt_tid[i]][rt_rda[i]] <= rt_data[i];
        end
    end
  end
endmodule : cmt_archreg
