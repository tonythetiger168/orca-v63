// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - 雲端訓推卡 (參數化): Roc-C(4die/256T/75W) / Roc-D(6die/512T/350W) / Roc(8die/825T)
// + KV-cache + MoE 整合。統一封套, 依 NUM_DIES 與 MEM 類型區分產品。
`include "orca_pkg.sv"

module orca_v63_cloud_card
  import orca_pkg::*;
#(
  parameter int NUM_DIES   = 6,        // Roc-C=4, Roc-D=6, Roc=8
  parameter int TOPS_CLASS = 512,      // 256 / 512 / 825
  parameter bit LOW_POWER  = 0         // Roc-C LPDDR5 低成本
)(
  input  logic clk, rst_n,
  input  uop_t  aix_uop,
  input  logic  aix_valid,
  output logic  aix_ready,
  output logic  aix_irq,
  output logic [NUM_DIES*3-1:0] hbm_ck_t, hbm_ck_c, hbm_cs_n,
  // 卡間 scale-out (1024-node fabric)
  input  logic [CLOUD_NOC_W+31:0] fabric_in  [4],
  input  logic                  fabric_in_v [4],
  output logic                  fabric_in_r [4],
  output logic [CLOUD_NOC_W+31:0] fabric_out [4],
  output logic                  fabric_out_v[4],
  input  logic                  fabric_out_r[4]
);
  // 每 die: AI tile (NCLUSTERS=2 縮減控記憶體, 雲端語意不變)
  uop_t  d_aix [NUM_DIES]; logic d_av [NUM_DIES], d_ar [NUM_DIES], d_irq [NUM_DIES];
  flit_t d_no  [NUM_DIES], d_ni  [NUM_DIES];
  logic  d_nor [NUM_DIES], d_niv [NUM_DIES], d_nir [NUM_DIES];

  genvar g;
  generate
    for (g = 0; g < NUM_DIES; g++) begin : g_die
      orca_v63_ai_tile #(.TILE_ID(g), .NCLUSTERS(2)) u_die (
        .clk(clk), .rst_n(rst_n),
        .aix_uop(d_aix[g]), .aix_valid(d_av[g]), .aix_ready(d_ar[g]),
        .noc_out(d_no[g]), .noc_out_ready(d_nor[g]),
        .noc_in(d_ni[g]), .noc_in_valid(d_niv[g]), .noc_in_ready(d_nir[g]),
        .aix_irq(d_irq[g]),
        .hbm_ck_t(hbm_ck_t[g*3 +: 3]), .hbm_ck_c(hbm_ck_c[g*3 +: 3]),
        .hbm_cs_n(hbm_cs_n[g*3 +: 3]));
      assign d_aix[g] = (g == 0) ? aix_uop : `UOP_NOP;
      assign d_av[g]  = (g == 0) ? aix_valid : 1'b0;
      assign d_ni[g]  = `FLIT_EMPTY; assign d_nor[g] = 1'b1; assign d_niv[g] = 1'b0;
    end
  endgenerate
  assign aix_ready = d_ar[0];
  assign aix_irq   = |{d_irq};

  // KV-cache + MoE (全卡共享)
  logic [31:0] kv_free;
  npu_kv_cache #(.HEAD_DIM(128), .NUM_KV_HEAD(8)) u_kv (
    .clk(clk), .rst_n(rst_n),
    .alloc_req(1'b0), .alloc_num_pages('0), .alloc_base_page(), .alloc_ok(),
    .free_req(1'b0), .free_base_page('0),
    .bt_we(1'b0), .bt_seq_id('0), .bt_slot('0), .bt_page('0), .bt_valid(1'b0),
    .bt_rd_page(), .bt_rd_valid(),
    .kv_we(1'b0), .kv_page('0), .kv_offset('0), .kv_wdata('0),
    .kv_rdata(), .kv_rd(1'b0), .kv_hit(), .free_pages(kv_free));
  npu_moe_router #(.D_MODEL(4096), .NUM_EXPERTS(MOE_MAX_EXPERTS), .TOP_K(8)) u_moe (
    .clk(clk), .rst_n(rst_n), .route_valid(1'b0), .hidden_state('0),
    .gate_weight('0), .num_experts(32'd64), .route_ready(), .topk_expert_id(),
    .topk_gate_score(), .route_done(), .ep_dispatch(), .ep_return('0));

  // 卡間 fabric (die 0 主埠)
  orca_cloud_fabric #(.MAX_NODES(CLOUD_MAX_NODES)) u_fabric (
    .clk(clk), .rst_n(rst_n), .my_x(11'd0), .my_y(11'd0),
    .inj_flit({d_no[0].payload, 22'd0}), .inj_valid(d_no[0].valid), .inj_ready(d_nir[0]),
    .eject_flit(), .eject_valid(),
    .port_in(fabric_in), .port_in_v(fabric_in_v), .port_in_r(fabric_in_r),
    .port_out(fabric_out), .port_out_v(fabric_out_v), .port_out_r(fabric_out_r));
endmodule : orca_v63_cloud_card
