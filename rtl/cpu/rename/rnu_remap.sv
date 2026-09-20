// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.3
`include "orca_pkg.sv"


// 重命名頂層: RAT + freelist, rd!=0 配發新 prd, 分支檢查點, trap flush
// v6.3.3: freelist 接入 flush 恢復 (全量重建, 見 rnu_freelist 註解)
module rnu_remap
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t [DECODE_WIDTH-1:0] in_uop,
  input  logic [DECODE_WIDTH-1:0] in_valid,
  output logic [DECODE_WIDTH-1:0] in_ready,
  output uop_t [DECODE_WIDTH-1:0] out_uop,
  output logic [DECODE_WIDTH-1:0] out_valid,
  input  logic [DECODE_WIDTH-1:0] disp_ready,
  input  logic br_mispredict,
  input  rob_idx_t br_rob_idx,
  input  tid_t br_tid,
  input  logic flush_valid,
  /* verilator coverage_off */  // LCOV_EXCL: cpu_core 以常數 tid 驅動, toggle 結構不可達
  input  tid_t flush_tid,
  /* verilator coverage_on */
  input  phys_reg_idx_t flush_map [32],
  input  logic [RETIRE_WIDTH-1:0] rt_req,
  input  phys_reg_idx_t [RETIRE_WIDTH-1:0] rt_prd_old
);
  import orca_pkg::*;
  logic [DECODE_WIDTH-1:0] need_rd, alloc_req, gnt;
  phys_reg_idx_t [DECODE_WIDTH-1:0] prd_f, prs1, prs2, pold;
  logic [1:0] ckpt_id;
  arch_reg_idx_t [DECODE_WIDTH-1:0] rs1a, rs2a, rda;
  tid_t [DECODE_WIDTH-1:0] tids;
  logic [DECODE_WIDTH-1:0] fpf;
  always_comb begin
    for (int s = 0; s < DECODE_WIDTH; s++) begin
      need_rd[s] = in_valid[s] && (in_uop[s].rd != 0) && !in_uop[s].is_store
                   && !in_uop[s].is_branch && (in_uop[s].opcode != OP_FENCE);
      alloc_req[s] = need_rd[s];
      rs1a[s] = in_uop[s].rs1; rs2a[s] = in_uop[s].rs2;
      rda[s]  = in_uop[s].rd;  tids[s] = in_uop[s].tid;
      fpf[s]  = in_uop[s].is_fp;
      in_ready[s]  = gnt[s] && disp_ready[s];
      out_valid[s] = in_valid[s] && in_ready[s];
      out_uop[s]         = in_uop[s];
      out_uop[s].prs1    = prs1[s];
      out_uop[s].prs2    = prs2[s];
      out_uop[s].prd     = need_rd[s] ? prd_f[s] : phys_reg_idx_t'(0);
      out_uop[s].prd_old = pold[s];
    end
  end
  rnu_freelist #(.POOL_SIZE(INT_PRF_ENTRIES)) u_fl (
    .clk(clk), .rst_n(rst_n),
    .alloc_req(alloc_req), .alloc_prd(prd_f), .alloc_gnt(gnt), .empty(),
    .dealloc_req(rt_req), .dealloc_prd(rt_prd_old),
    .flush_valid(flush_valid), .flush_map(flush_map));
  rnu_rat u_rat (
    .clk(clk), .rst_n(rst_n),
    .tid_i(tids), .rs1a(rs1a), .rs2a(rs2a), .rda(rda),
    .rd_we(in_ready), .prd_i(prd_f), .is_fp(fpf),
    .prs1_o(prs1), .prs2_o(prs2), .prd_old_o(pold),
    .ckpt_push(in_valid[0] && in_uop[0].is_branch && in_ready[0]),
    .ckpt_tid(in_uop[0].tid), .ckpt_id(ckpt_id),
    .ckpt_restore(br_mispredict), .restore_tid(br_tid), .restore_id(ckpt_id),
    .flush_thread(flush_valid), .flush_tid(flush_tid), .flush_map(flush_map));
endmodule : rnu_remap
