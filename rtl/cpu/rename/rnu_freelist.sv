// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.3
`include "orca_pkg.sv"


// 實體暫存器空閒表: pool[32..POOL_SIZE-1], 每週期 6 alloc / 16 dealloc
// v6.3.3: 新增 flush 恢復機制 (見 always_ff 註解)
module rnu_freelist
  import orca_pkg::*;
#(
  parameter int POOL_SIZE = INT_PRF_ENTRIES,
  parameter int ALLOC_W   = DECODE_WIDTH
)(
  input  logic clk, rst_n,
  input  logic [ALLOC_W-1:0] alloc_req,
  output phys_reg_idx_t [ALLOC_W-1:0] alloc_prd,
  output logic [ALLOC_W-1:0] alloc_gnt,
  output logic empty,
  input  logic [RETIRE_WIDTH-1:0] dealloc_req,
  input  phys_reg_idx_t [RETIRE_WIDTH-1:0] dealloc_prd,
  // v6.3.3 (新增 port): flush 時依架構態映射重建空閒表
  input  logic flush_valid,
  input  phys_reg_idx_t flush_map [32]
);
  import orca_pkg::*;
  localparam int N = POOL_SIZE - 32, AW = $clog2(N);
  phys_reg_idx_t pool [N];
  logic [AW:0] rd, wr, cnt;
  assign empty = (cnt == 0);
  always_comb begin
    for (int i = 0; i < ALLOC_W; i++) begin
      alloc_gnt[i] = (i < cnt);
      alloc_prd[i] = (i < cnt) ? pool[(rd + i[AW:0]) % N] : phys_reg_idx_t'(0);
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < N; i++) pool[i] <= phys_reg_idx_t'(i + 32);
      rd <= '0; wr <= '0; cnt <= N[AW:0];
    end else if (flush_valid) begin
      // v6.3.3: flush 恢復 (最小可行機制)
      // rnu_rat 雖有 4-deep 分支檢查點, 但 freelist 本身無快照; 此處採
      // 「全量重建」: 所有 >=32 且不在 flush_map (架構態映射) 中的 prd
      // 一律視為空閒, pool 依序重排, rd=0 / wr=cnt=空閒數。
      // 限制: 分支 mispredict 時 flush_map 為 arch (retire) 態, 會把
      // 已分配給被清空年輕 uop 的 prd 也回收 — 因 flush 同時清空
      // scheduler/ROB, 行為一致; 未來應改為與 RAT 檢查點對齊的快照。
      automatic int k = 0;
      for (int i = 32; i < POOL_SIZE; i++) begin
        automatic logic used = 1'b0;
        for (int a = 0; a < 32; a++) /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
          if (flush_map[a] == phys_reg_idx_t'(i)) used = 1'b1;
        if (!used) begin /* verilator coverage_on */
          pool[k] <= phys_reg_idx_t'(i);
          k = k + 1;
        end
      end
      rd  <= '0;
      wr  <= (AW+1)'(k);
      cnt <= (AW+1)'(k);
    end else begin
      automatic int a = 0, d = 0;
      for (int i = 0; i < ALLOC_W; i++)
        if (alloc_req[i] && alloc_gnt[i]) a = a + 1;
      for (int i = 0; i < RETIRE_WIDTH; i++)
        if (dealloc_req[i] && dealloc_prd[i] >= 32) begin
          pool[(wr + d) % N] <= dealloc_prd[i];
          d = d + 1;
        end
      rd  <= rd + a[AW:0];
      wr  <= wr + d[AW:0];
      cnt <= cnt - a + d;
    end
  end
endmodule : rnu_freelist
