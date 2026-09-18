// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 重命名別名表: SMT×(32 int + 32 fp), 12-wide 讀寫, 4-deep 分支檢查點
module rnu_rat
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  tid_t [DISPATCH_WIDTH-1:0] tid_i,
  input  arch_reg_idx_t [DISPATCH_WIDTH-1:0] rs1a, rs2a, rda,
  input  logic [DISPATCH_WIDTH-1:0] rd_we,
  input  phys_reg_idx_t [DISPATCH_WIDTH-1:0] prd_i,
  input  logic [DISPATCH_WIDTH-1:0] is_fp,
  output phys_reg_idx_t [DISPATCH_WIDTH-1:0] prs1_o, prs2_o,
  output phys_reg_idx_t [DISPATCH_WIDTH-1:0] prd_old_o,
  input  logic ckpt_push,
  input  tid_t ckpt_tid,
  output logic [1:0] ckpt_id,
  input  logic ckpt_restore,
  input  tid_t restore_tid,
  input  logic [1:0] restore_id,
  input  logic flush_thread,
  input  tid_t flush_tid,
  input  phys_reg_idx_t flush_map [32]
);
  import orca_pkg::*;
  phys_reg_idx_t irat [SMT_THREADS][32];
  phys_reg_idx_t frat [SMT_THREADS][32];
  phys_reg_idx_t ick  [SMT_THREADS][4][32];
  phys_reg_idx_t fck  [SMT_THREADS][4][32];
  logic [1:0] ckpt_ptr [SMT_THREADS];
  always_comb begin
    for (int s = 0; s < DISPATCH_WIDTH; s++) begin
      prs1_o[s]    = is_fp[s] ? frat[tid_i[s]][rs1a[s]] : irat[tid_i[s]][rs1a[s]];
      prs2_o[s]    = is_fp[s] ? frat[tid_i[s]][rs2a[s]] : irat[tid_i[s]][rs2a[s]];
      prd_old_o[s] = is_fp[s] ? frat[tid_i[s]][rda[s]]  : irat[tid_i[s]][rda[s]];
      for (int p = 0; p < s; p++)
        if (rd_we[p] && rda[p] == rs1a[s] && tid_i[p] == tid_i[s]) prs1_o[s] = prd_i[p];
      for (int p = 0; p < s; p++)
        if (rd_we[p] && rda[p] == rs2a[s] && tid_i[p] == tid_i[s]) prs2_o[s] = prd_i[p];
    end
  end
  assign ckpt_id = ckpt_ptr[ckpt_tid];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int t = 0; t < SMT_THREADS; t++) begin
        ckpt_ptr[t] <= '0;
        for (int a = 0; a < 32; a++) begin
          irat[t][a] <= phys_reg_idx_t'(a);
          frat[t][a] <= phys_reg_idx_t'(a);
        end
      end
    end else begin
      for (int s = 0; s < DISPATCH_WIDTH; s++)
        if (rd_we[s] && rda[s] != 0) begin
          if (is_fp[s]) frat[tid_i[s]][rda[s]] <= prd_i[s];
          else          irat[tid_i[s]][rda[s]] <= prd_i[s];
        end
      if (ckpt_push) begin
        ick[ckpt_tid][ckpt_ptr[ckpt_tid]] <= irat[ckpt_tid];
        fck[ckpt_tid][ckpt_ptr[ckpt_tid]] <= frat[ckpt_tid];
        ckpt_ptr[ckpt_tid] <= ckpt_ptr[ckpt_tid] + 1'b1;
      end
      if (ckpt_restore) begin
        irat[restore_tid] <= ick[restore_tid][restore_id];
        frat[restore_tid] <= fck[restore_tid][restore_id];
        ckpt_ptr[restore_tid] <= restore_id + 1'b1;
      end
      if (flush_thread) begin
        for (int a = 0; a < 32; a++) irat[flush_tid][a] <= flush_map[a];
        ckpt_ptr[flush_tid] <= '0;
      end
    end
  end
endmodule : rnu_rat
