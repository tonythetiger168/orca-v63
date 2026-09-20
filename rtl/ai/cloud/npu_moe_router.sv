// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - MoE 路由器 (Roc-E/Garuda): gate 打分 -> top-k 專家選擇 -> 分發/合併
`include "orca_pkg.sv"

module npu_moe_router #(
  parameter int D_MODEL    = 4096,
  parameter int NUM_EXPERTS = MOE_MAX_EXPERTS,   // 256
  parameter int TOP_K      = 8,
  parameter int NUM_GROUPS = 16                   // expert parallel group
)(
  input  logic clk, rst_n,
  input  logic                       route_valid,
  input  logic [D_MODEL-1:0]         hidden_state,
  input  logic [D_MODEL*NUM_EXPERTS-1:0] gate_weight, // 簡化: 預載 gate 矩陣
  input  logic [31:0]                num_experts,     // 實際啟用專家數
  output logic                       route_ready,
  output logic [TOP_K-1:0][7:0]      topk_expert_id,
  output logic [TOP_K-1:0][15:0]     topk_gate_score, // Q8.8
  output logic                       route_done,
  // 分發到 expert group (all-to-all)
  output logic [NUM_GROUPS-1:0]      ep_dispatch,
  input  logic [NUM_GROUPS-1:0]      ep_return
);
  import orca_pkg::*;
  typedef enum logic [1:0] {MR_IDLE, MR_SCORE, MR_TOPK, MR_DONE} mr_t;
  mr_t st;
  logic [NUM_EXPERTS-1:0][31:0] score;        // gate 點積累加
  logic [TOP_K-1:0][31:0]       topk_score;
  logic [TOP_K-1:0][7:0]        topk_id;

  // gate 點積: hidden · gate_col[e] (行為模型)
  always_comb begin
    logic [31:0] acc;
    acc = 32'd0;
    for (int e = 0; e < NUM_EXPERTS; e++) begin
      acc = 32'd0;
      if (e < num_experts)
        for (int d = 0; d < D_MODEL; d += 32)
          acc = acc + hidden_state[d +: 32] * gate_weight[e*D_MODEL + d +: 32];
      score[e] = acc;
    end
  end

  // top-k 選擇 (插入排序, 行為模型)
  logic [31:0] srt_s [NUM_EXPERTS];
  logic [7:0]  srt_id[NUM_EXPERTS];
  always_comb begin
    int best;
    logic [31:0] ts;  logic [7:0] ti;
    for (int e = 0; e < NUM_EXPERTS; e++) begin srt_s[e] = score[e]; srt_id[e] = 8'(e); end
    for (int k = 0; k < TOP_K; k++) begin
      best = k;
      for (int e = k+1; e < NUM_EXPERTS; e++) if (srt_s[e] > srt_s[best]) best = e;
      ts = srt_s[k];  ti = srt_id[k];
      srt_s[k] = srt_s[best]; srt_id[k] = srt_id[best]; srt_s[best] = ts; srt_id[best] = ti;
    end
    for (int k = 0; k < TOP_K; k++) begin
      topk_score[k] = 16'(srt_s[k] >> 16);  // Q8.8 量化
      topk_id[k]    = srt_id[k];
    end
  end

  // 分發: expert_id % NUM_GROUPS 決定 group
  always_comb begin
    ep_dispatch = '0;
    for (int k = 0; k < TOP_K; k++)
      ep_dispatch[topk_id[k] % NUM_GROUPS] = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= MR_IDLE; route_done <= 1'b0; end
    else begin
      route_done <= 1'b0;
      unique case (st)
        MR_IDLE:  if (route_valid) st <= MR_SCORE;
        MR_SCORE: st <= MR_TOPK;
        MR_TOPK: begin
          for (int k = 0; k < TOP_K; k++) begin
            topk_expert_id[k]   <= topk_id[k];
            topk_gate_score[k]  <= topk_score[k];
          end
          st <= MR_DONE;
        end
        MR_DONE: begin route_done <= 1'b1; st <= MR_IDLE; end
        default: st <= MR_IDLE;
      endcase
    end
  end
  assign route_ready = (st == MR_IDLE);
endmodule : npu_moe_router
