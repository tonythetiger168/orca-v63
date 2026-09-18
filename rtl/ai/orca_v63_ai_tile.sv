// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// AI Tile 頂層: AIX_INTF + GSCU + 16 Cluster + L2 SRAM + HBM3 + NoC 介面卡
module orca_v63_ai_tile
  import orca_pkg::*;
#(
  parameter int TILE_ID = 0,
  parameter int NCLUSTERS = CLUSTERS_PER_TILE   // lint override only
)(
  input  logic clk, rst_n,
  input  uop_t  aix_uop,
  input  logic  aix_valid,
  output logic  aix_ready,
  output flit_t noc_out,
  input  logic  noc_out_ready,
  input  flit_t noc_in,
  input  logic  noc_in_valid,
  output logic  noc_in_ready,
  output logic  aix_irq,
  output logic [HBM3_STACKS-1:0] hbm_ck_t, hbm_ck_c, hbm_cs_n,
  output logic  hbm_init_done          // v6.3.3: HBM3 PHY training complete (new port)
);
  import orca_pkg::*;
  aix_cmd_t ai_cmd, gscu_cl_cmd;
  logic ai_v, ai_r, gscu_cl_v, gscu_cl_r, gscu_irq;
  aix_tdb_t tdb_rd [AIX_NUM_TDB];
  logic [AIX_NUM_TDB-1:0] tdb_busy;
  logic [NCLUSTERS-1:0] cl_done, cl_busy;

  npu_aix_intf u_intf (
    .clk(clk), .rst_n(rst_n),
    .aix_uop(aix_uop), .aix_valid(aix_valid), .aix_ready(aix_ready),
    .cmd_out(ai_cmd), .cmd_valid(ai_v), .cmd_ready(ai_r),
    .completion(gscu_irq), .completion_valid(aix_irq),
    .tdb_we(1'b0), .tdb_idx('0), .tdb_wdata('0), .tdb_rd(tdb_rd));

  npu_gscu u_gscu (
    .clk(clk), .rst_n(rst_n),
    .cmd_in(ai_cmd), .cmd_valid(ai_v), .cmd_ready(ai_r),
    .irq(gscu_irq), .tdb_rd(tdb_rd), .tdb_busy(tdb_busy),
    .cl_cmd(gscu_cl_cmd), .cl_cmd_valid(gscu_cl_v), .cl_cmd_ready(gscu_cl_r),
    .cl_done(cl_done), .cl_busy(cl_busy),
    .attn_cmd_valid(attn_cmd_v), .attn_cmd_ready(attn_cmd_r), .attn_done(attn_done_w));

  genvar i;
  generate
    for (i = 0; i < NCLUSTERS; i++) begin : g_cl
      npu_cluster #(.CLUSTER_ID(i)) u_cl (
        .clk(clk), .rst_n(rst_n),
        .cmd(gscu_cl_cmd), .cmd_valid(gscu_cl_v), .cmd_ready(gscu_cl_r),
        .done(cl_done[i]), .busy(cl_busy[i]));
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // v6.3.3: npu_attn_engine 接入 (原註解排在 v6.3.4, 提前)
  // GSCU 把 attention 類 AIX uop (AIX_OP_ATTN_QK / AIX_OP_ATTN_AV) 分派到
  // attn engine; engine 透過 L2 SRAM 埠 (active 時擁有 L2 1R1W 埠) 存取
  // Q/K/V/Output, 完成後 done 回報 GSCU, GSCU 等 drain 後發 irq。
  // ---------------------------------------------------------------------------
  logic     attn_cmd_v, attn_cmd_r, attn_done_w, attn_start, attn_active;
  aix_cmd_t attn_cmd_q;

  assign attn_cmd_r = !attn_active;          // engine idle => 可接受新 attn cmd
  assign attn_start = attn_cmd_v && attn_cmd_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      attn_active <= 1'b0;
      attn_cmd_q  <= '0;
    end else begin
      if (attn_start) begin
        attn_active <= 1'b1;
        attn_cmd_q  <= gscu_cl_cmd;   // latch 分派到的 attention 命令
      end
      if (attn_done_w) attn_active <= 1'b0;
    end
  end

  // attention 命令欄位 -> engine 配置; TDB base_addr -> Q/K/V/Out 基底
  localparam int TDB_IDX_W = $clog2(AIX_NUM_TDB);
  logic [15:0] attn_seq_len;
  logic [63:0] attn_q_base, attn_k_base, attn_v_base, attn_o_base;
  assign attn_seq_len = (attn_cmd_q.length[15:0] == 16'd0) ? 16'd16
                                                           : attn_cmd_q.length[15:0];
  assign attn_q_base  = tdb_rd[attn_cmd_q.tdb0[TDB_IDX_W-1:0]].base_addr;
  assign attn_k_base  = tdb_rd[attn_cmd_q.tdb1[TDB_IDX_W-1:0]].base_addr;
  assign attn_v_base  = tdb_rd[attn_cmd_q.tdb1[TDB_IDX_W-1:0]].base_addr; // K/V 共用 handle B
  assign attn_o_base  = tdb_rd[attn_cmd_q.tdb2[TDB_IDX_W-1:0]].base_addr;

  logic [63:0]  attn_l2_addr;
  logic         attn_l2_v, attn_l2_we, attn_l2_rsp_v;
  logic [511:0] attn_l2_wdata;
  logic [63:0]  attn_hbm_addr;   // KV-cache 路徑 v6.3.4 仲裁 (engine 內部 tie 0)
  logic         attn_hbm_v;

  assign attn_l2_rsp_v = attn_l2_v && !attn_l2_we;  // L2 讀取為組合邏輯, 同週期回 data

  npu_attn_engine u_attn (
    .clk(clk), .rst_n(rst_n), .clk_gate(1'b1),
    .start(attn_start), .done(attn_done_w),
    .attn_config(attn_cmd_q.flags[2:0]),
    .seq_len(attn_seq_len),
    .head_dim(8'd64), .num_heads(8'd8), .num_kv_heads(8'd8),
    .dtype(3'd2),                       // BF16
    .use_rope(1'b0), .use_alibi(1'b0), .alibi_slope(32'h0),
    .l2_req_addr(attn_l2_addr), .l2_req_valid(attn_l2_v), .l2_req_we(attn_l2_we),
    .l2_rsp_data(l2_rd_data_w), .l2_rsp_valid(attn_l2_rsp_v),
    .hbm3_req_addr(attn_hbm_addr), .hbm3_req_valid(attn_hbm_v),
    .hbm3_rsp_data(hbm_rsp_data_w), .hbm3_rsp_valid(hbm_ack_w),
    .cycle_counter(), .max_score(), .overflow_flag(),
    .q_base(attn_q_base), .k_base(attn_k_base),
    .v_base(attn_v_base), .o_base(attn_o_base),
    .l2_req_data(attn_l2_wdata));

  // DMA <-> L2 <-> HBM3 資料路徑 (v6.3.3)
  logic [511:0] l2_rd_data_w;
  logic         l2_rd_req_w, l2_wr_req_w;
  logic [31:0]  l2_rd_addr_w, l2_wr_addr_w;
  logic [511:0] l2_wr_data_w;   /*verilator coverage_off*/ // dma_l2_addr/hbm_addr_w/hbm_we_w tie-off stub 常數折疊 (工具限制)
  logic [31:0]  dma_l2_addr;
  paddr_t       hbm_addr_w;
  logic         hbm_req_w, hbm_we_w, hbm_ack_w;  /*verilator coverage_on*/
  logic [511:0] hbm_rsp_data_w, hbm_req_data_w;

  // L2 1R1W 埠仲裁: attn engine active 時擁有 L2 埠; 否則保留給 DMA 路徑
  // (DMA desc 驅動排 v6.3.4, 現階段 req tie 0)
  assign l2_rd_addr_w = attn_active ? attn_l2_addr[31:0] : dma_l2_addr;
  assign l2_wr_addr_w = attn_active ? attn_l2_addr[31:0] : dma_l2_addr;
  assign l2_rd_req_w  = attn_active ? (attn_l2_v && !attn_l2_we) : 1'b0;
  assign l2_wr_req_w  = attn_active ? (attn_l2_v &&  attn_l2_we) : 1'b0;
  assign l2_wr_data_w = attn_active ? attn_l2_wdata : hbm_rsp_data_w;

  npu_l2_sram u_l2 (
    .clk(clk), .rst_n(rst_n),
    .rd_addr(l2_rd_addr_w), .rd_req(l2_rd_req_w), .rd_data(l2_rd_data_w),
    .wr_addr(l2_wr_addr_w), .wr_req(l2_wr_req_w), .wr_data(l2_wr_data_w),
    .scrub_en(1'b1), .ecc_err());

  npu_dma u_dma (
    .clk(clk), .rst_n(rst_n),
    .desc('0), .desc_valid(1'b0), .desc_ready(), .done(),
    .l2_addr(dma_l2_addr), .l2_req(), .l2_rdata(l2_rd_data_w),
    .l2_wdata(), .l2_we(),
    .hbm_addr(hbm_addr_w), .hbm_req(hbm_req_w), .hbm_we(hbm_we_w),
    .hbm_rdata(hbm_rsp_data_w), .hbm_wdata(hbm_req_data_w),
    .hbm_ack(hbm_ack_w));
  // v6.3.4: DMA desc 驅動後 l2_rd_req_w/l2_wr_req_w 的 DMA 側啟用 (現 tie 0, 見上方 mux)

  npu_tile_noc u_noc (
    .clk(clk), .rst_n(rst_n),
    .dma_addr('0), .dma_valid(1'b0), .dma_is_write(1'b0), .dma_wdata('0),
    .dma_ready(), .dma_rdata(),
    .noc_out(noc_out), .noc_out_ready(noc_out_ready),
    .noc_in(noc_in), .noc_in_valid(noc_in_valid), .noc_in_ready(noc_in_ready),
    .vc_credit({NOC_VC{1'b1}}));

  // v6.3.3: ctrl 的 PHY 側命令/時脈先進 npu_hbm3_phy, 訓練完成後由 PHY
  // 轉送到 tile 對外的 HBM pin (hbm_ck_t/hbm_ck_c/hbm_cs_n)
  logic [HBM3_STACKS-1:0] ctrl_ck_t, ctrl_ck_c, ctrl_cs_n;

  npu_hbm3_ctrl #(.NUM_STACKS(HBM3_STACKS)) u_hbm3 (
    .clk(clk), .clk_phy(clk), .rst_n(rst_n),
    .req_valid(hbm_req_w), .req_addr(hbm_addr_w), .req_we(hbm_we_w),
    .req_data(hbm_req_data_w), .req_be(64'hFFFF_FFFF_FFFF_FFFF), .req_ready(),
    .rsp_data(hbm_rsp_data_w), .rsp_valid(hbm_ack_w),
    .phy_ck_t(ctrl_ck_t), .phy_ck_c(ctrl_ck_c), .phy_cs_n(ctrl_cs_n),
    .phy_cke(), .phy_rst_n(), .phy_ca(), .phy_rwds(),
    .cfg_tRFC(16'h0090), .cfg_tREFI(16'h2000),
    .cfg_CL(8'h22), .cfg_CWL(8'h20), .cfg_RL(8'h22), .cfg_WL(8'h20),
    .cfg_ecc_en(1'b1), .cfg_scrub_en(1'b1),
    .stack_temp(), .stack_alert_n(),
    .total_reads(), .total_writes(), .total_refreshes(), .ecc_error_count());

  // v6.3.3: npu_hbm3_phy 接通 — 上電後跑 ZQ/MR/read-leveling 訓練序列,
  // P_DONE 後將 controller 的 ck/cs 轉送到 HBM pin; init_done 拉到 tile 端口
  npu_hbm3_phy u_hbm3_phy (
    .clk(clk), .rst_n(rst_n),
    .init_start(1'b1), .init_done(hbm_init_done),
    .ck_t(hbm_ck_t), .ck_c(hbm_ck_c), .cs_n(hbm_cs_n),
    .rdly_count(8'd32),
    .mr_addr(), .mr_wdata(), .mr_we(),
    .ctrl_ck_t(ctrl_ck_t), .ctrl_ck_c(ctrl_ck_c), .ctrl_cs_n(ctrl_cs_n));
endmodule : orca_v63_ai_tile
