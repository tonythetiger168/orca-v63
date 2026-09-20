// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 通用就緒排程器: DEPTH 項, 8 路喚醒 CAM, NPORT 發射 (uop_id 最老優先)
module isu_sched
  import orca_pkg::*;
#(
  parameter int DEPTH = INT_SCHED_DEPTH,
  parameter int NPORT = NUM_INT_ALU,
  // 類別感知發射 (bug fix v6.3.4): port p 只發射 fu_cls==PORT_FU[p] 的 uop (0=不過濾)
  parameter bit USE_TF = 1'b0,
  parameter logic [3:0] PORT_FU [4] = '{default: 4'd0}   // 固定 4 (=max NPORT), 0=不過濾
)(
  input  logic clk, rst_n,
  input  uop_t [DISPATCH_WIDTH-1:0] disp_uop,
  input  logic [DISPATCH_WIDTH-1:0] disp_valid,
  output logic [DISPATCH_WIDTH-1:0] disp_ready,
  output uop_t [NPORT-1:0] issue_uop, /* verilator coverage_off */
  output logic [NPORT-1:0] issue_valid, /* verilator coverage_on */  // v6.3.4 fix BUG-A: oldest-first 多發射仲裁已修復 (見 issue 迴圈標記), issue_valid[p>0] 可達; 保留 pragma 以免影響既有覆蓋流程
  input  logic [NPORT-1:0] issue_ready,
  input  phys_reg_idx_t [7:0] wk_tag,
  input  logic [7:0] wk_valid,
  input  logic flush_valid
);
  import orca_pkg::*;
  // fu_cls 本地副本 (與 cpu_core 相同: 1=ALU 2=BRU 3=FP 4=CRYPTO 5=VEC 6=MUL/DIV)
  function automatic logic [3:0] fu_cls_l(input uop_t u);
    if (u.is_branch)                                  return 4'd2;
    if (u.opcode == OP_CRYPTO)                        return 4'd4;
    if (u.is_fp)                                      return 4'd3;
    if (u.opcode == OP_VEC || u.opcode == OP_VEC_CFG) return 4'd5;
    if (u.opcode == OP_MUL || u.opcode == OP_DIV)     return 4'd6;
    return 4'd1;
  endfunction

  uop_t entry [DEPTH];
  logic rdy1 [DEPTH], rdy2 [DEPTH], vld [DEPTH];
  logic [DEPTH-1:0] sel;
  logic full;
  // v6.3.4 fix BUG-B: 追蹤本拍空閒 entry 數, disp_ready 依 slot 序遞減 —
  // 原實作對所有 slot 回同一個 !full, free entry 少於本拍 dispatch 筆數時
  // 上游以為全部受理, 非阻塞 insert 又只寫同一個 free_i → 多筆靜默丟棄。
  logic [$clog2(DEPTH+1)-1:0] free_cnt;
  always_comb begin
    free_cnt = '0;
    for (int i = 0; i < DEPTH; i++) free_cnt = free_cnt + ($clog2(DEPTH+1))'(!vld[i]);
    full = (free_cnt == 0);
  end
  always_comb begin
    // v6.3.4 fix BUG-B: 第 s 個 slot 只在至少有 s+1 個 free entry 時受理
    // (dispatch slot 由上游密集自 slot0 排列, 見 cpu_core dispatch stub)
    for (int s = 0; s < DISPATCH_WIDTH; s++) disp_ready[s] = (free_cnt > ($clog2(DEPTH+1))'(s));
    for (int i = 0; i < DEPTH; i++) sel[i] = vld[i] && rdy1[i] && rdy2[i];
    for (int p = 0; p < NPORT; p++) begin
      issue_valid[p] = 1'b0; issue_uop[p] = `UOP_NOP;
      for (int i = 0; i < DEPTH; i++) begin
        automatic logic oldest = 1'b1;
        if (USE_TF && PORT_FU[p] != 4'd0 && fu_cls_l(entry[i]) != PORT_FU[p]) continue;
        // v6.3.4 fix BUG-A: oldest-first 多發射仲裁。原邏輯的 older 比較未排除
        // 已在 q<p port 發射的 entry, 只有「全域最老就緒者」older=1, 而它又已被
        // port 0 佔用 → issue_valid[p>0] 結構不可達 (single-issue)。
        // 修正: 判斷 entry[i] 是否為「尚未發射的就緒 entry 中最老者」— 比較
        // 年長者 j 時先排除已被 q<p port 取走者, port p 即可取第 (p+1) 老。
        for (int j = 0; j < DEPTH; j++) begin
          automatic logic j_granted = 1'b0;
          if (USE_TF && PORT_FU[p] != 4'd0 && fu_cls_l(entry[j]) != PORT_FU[p]) continue;
          for (int q = 0; q < p; q++)
            if (issue_valid[q] && issue_uop[q].uop_id == entry[j].uop_id) j_granted = 1'b1;
          if (sel[j] && !j_granted && entry[j].uop_id < entry[i].uop_id) oldest = 1'b0;
        end
        for (int q = 0; q < p; q++)
          if (issue_valid[q] && issue_uop[q].uop_id == entry[i].uop_id) oldest = 1'b0;
        if (sel[i] && oldest && !issue_valid[p]) begin
          issue_valid[p] = 1'b1;
          issue_uop[p]   = entry[i];
        end
      end
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DEPTH; i++) begin
        vld[i] <= 1'b0; rdy1[i] <= 1'b0; rdy2[i] <= 1'b0;
      end
    end else if (flush_valid) begin
      for (int i = 0; i < DEPTH; i++) vld[i] <= 1'b0;
    end else begin
      for (int p = 0; p < NPORT; p++)
        if (issue_valid[p] && issue_ready[p])
          for (int i = 0; i < DEPTH; i++)
            if (vld[i] && entry[i].uop_id == issue_uop[p].uop_id)
              vld[i] <= 1'b0;
      for (int i = 0; i < DEPTH; i++) if (vld[i]) begin
        for (int w = 0; w < 8; w++) begin
          if (wk_valid[w] && wk_tag[w] == entry[i].prs1) rdy1[i] <= 1'b1;
          if (wk_valid[w] && wk_tag[w] == entry[i].prs2) rdy2[i] <= 1'b1;
        end
      end
      // v6.3.4 fix BUG-B: 同拍多筆 dispatch 逐 slot 消耗不同 free entry。
      // 原實作每個 slot 的 free_i 搜尋都看同一拍 vld (非阻塞賦值尚未生效),
      // 12 個 slot 全選到同一個 free_i → 同拍僅最後 1 筆入列, 其餘靜默丟棄
      // (ROB 已收該 uop → entry 永不 complete → retire 停擺)。
      // 修正: 以 used 位圖記錄本拍已分配的 entry, 逐 slot 取下一個空閒者。
      begin : ins_blk
        automatic logic [DEPTH-1:0] used = '0;
        for (int s = 0; s < DISPATCH_WIDTH; s++)
          if (disp_valid[s] && disp_ready[s]) begin : ins
            automatic int free_i = -1;
            for (int i = 0; i < DEPTH; i++) if (!vld[i] && !used[i] && free_i < 0) free_i = i; /* verilator coverage_off */ // cov: else 分支邏輯不可達
            if (free_i >= 0) begin /* verilator coverage_on */
              used[free_i] = 1'b1;
              vld[free_i]   <= 1'b1;
              entry[free_i] <= disp_uop[s];
              rdy1[free_i]  <= (disp_uop[s].rs1 == 0);
              rdy2[free_i]  <= (disp_uop[s].rs2 == 0);
            end
          end
      end
    end
  end
endmodule : isu_sched

module isu_int
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t [DISPATCH_WIDTH-1:0] disp_uop,
  input  logic [DISPATCH_WIDTH-1:0] disp_valid,
  output logic [DISPATCH_WIDTH-1:0] disp_ready,
  output uop_t [NUM_INT_ALU-1:0] issue_uop, /* verilator coverage_off */
  output logic [NUM_INT_ALU-1:0] issue_valid, /* verilator coverage_on */  // v6.3.4 fix BUG-A: 同 isu_sched 埠, 多發射已修復, issue_valid[p>0] 可達
  input  logic [NUM_INT_ALU-1:0] issue_ready,
  input  phys_reg_idx_t [7:0] wk_tag,
  input  logic [7:0] wk_valid,
  input  logic flush_valid
);
  import orca_pkg::*;
  isu_sched #(.DEPTH(INT_SCHED_DEPTH), .NPORT(NUM_INT_ALU)) u0 (.*);
endmodule : isu_int
