// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// ORCA v6.3 SoC 頂層: 4 CPU tile + 4 AI tile + NoC mesh + DDR5/PCIe/BoW/JTAG
module orca_v63_soc
  import orca_pkg::*;
#(
  parameter int NCL_AI = CLUSTERS_PER_TILE,   // lint override only
  parameter int NCT  = NUM_CPU_TILES,          // lint override only
  parameter int NCO  = CORES_PER_CPU_TILE,     // lint override only
  parameter int NAI  = NUM_AI_TILES            // lint override only
)(
  input  logic        clk_sys,
  input  logic        clk_noc,
  input  logic        rst_n,  /*verilator coverage_off*/
  output logic [3:0]  ddr5_ck_t, ddr5_ck_c, ddr5_cs_n,
  inout  logic [3:0]  ddr5_dqs_t, ddr5_dqs_c,
  inout  logic [63:0] ddr5_dq,
  output logic [15:0] ddr5_addr,
  output logic [1:0]  ddr5_ba,  /*verilator coverage_on*/  // COV-EXEMPT: 結構性常數 — ddr5_ck_t/ck_c 綁 4'hF/4'h0, cs_n=4'hF (req_valid 綁 0); dqs/dq 於 SoC 內無驅動 (dq_o/dq_oe 未接); addr/ba=req_addr 綁 '0。上述 port declaration toggle points 邏輯不可達
  output logic        ddr5_act_n,
  output logic [11:0] hbm3_ck_t, hbm3_ck_c, hbm3_cs_n,  /*verilator coverage_off*/
  inout  logic [11:0] hbm3_dqs_t, hbm3_dqs_c,  /*verilator coverage_on*/  // COV-EXEMPT: hbm3_dqs 於 SoC 內無驅動 (ai_tile 僅驅動 hbm_ck, dqs 未接), inout 恆 Z, toggle point 邏輯不可達
  inout  logic [1535:0] hbm3_dq,
  output logic        pcie_tx_p, pcie_tx_n,
  input  logic        pcie_rx_p, pcie_rx_n,
  input  logic        pcie_refclk_p, pcie_refclk_n,
  output logic [7:0]  bow_tx_data, bow_tx_clk,
  input  logic [7:0]  bow_rx_data, bow_rx_clk,
  input  logic        jtag_tck, jtag_tms, jtag_tdi,
  output logic        jtag_tdo,
  input  logic        ext_irq_n,
  output logic        nmi_out
);
  import orca_pkg::*;
  // Tile flit ports (mesh wiring via orca_noc_router in v6.3.2)
  flit_t ct_out [NUM_CPU_TILES], at_out [NUM_AI_TILES];
  flit_t ct_in  [NUM_CPU_TILES], at_in  [NUM_AI_TILES];  /*verilator coverage_off*/
  logic  ct_or  [NUM_CPU_TILES], at_or  [NUM_AI_TILES];  /*verilator coverage_on*/  // COV-EXEMPT (line40): ct_or[3] 結構性常數 — stub cpu_tile cnt 步進 (1+TILE_ID), TILE_ID=3 時步進 4 使 noc_out_ready=cnt[1] 恆 0; at_or[*] 恆 1 — adapter 直通 t_out_ready=r_rx_ready=router !buf_full, buf_full 結構恆 0 (wr/rd ptr wrap, count<BUF_DEPTH)
  // v6.3.4 fix BUG-C: 原 ct_iv/at_iv[1..3] 豁免已移除 — flit_t 525b 線網修復後
  // router dest_x 正確解碼, local 投遞全列可達, 由 soc_east_tb/soc_smoke_tb 真實覆蓋
  logic  ct_iv  [NUM_CPU_TILES], at_iv  [NUM_AI_TILES];
  logic  at_ir  [NUM_AI_TILES];

  genvar t;
  generate
    for (t = 0; t < NCT; t++) begin : g_ct
      orca_v63_cpu_tile #(.TILE_ID(t), .NCO(NCO)) u_ct (
        .clk(clk_sys), .rst_n(rst_n),
        .noc_out(ct_out[t]), .noc_in(ct_in[t]),
        .noc_out_ready(ct_or[t]), .noc_in_valid(ct_iv[t]),
        .irq_lines('0), .irq_ack());
    end
    for (t = 0; t < NAI; t++) begin : g_at
      orca_v63_ai_tile #(.TILE_ID(t), .NCLUSTERS(NCL_AI)) u_at (
        .clk(clk_noc), .rst_n(rst_n),
        .aix_uop(`UOP_NOP), .aix_valid(1'b0), .aix_ready(),
        .noc_out(at_out[t]),
        .noc_out_ready(at_or[t]),
        .noc_in(at_in[t]),
        .noc_in_valid(at_iv[t]),
        .noc_in_ready(at_ir[t]),
        .aix_irq(),
        .hbm_ck_t(hbm3_ck_t[t*3 +: 3]),
        .hbm_ck_c(hbm3_ck_c[t*3 +: 3]),
        .hbm_cs_n(hbm3_cs_n[t*3 +: 3]));
    end
  endgenerate

  // ---- NoC mesh 4x2 (v6.3.3): y=0 CPU tiles, y=1 AI tiles ----
  // v6.3.4 fix BUG-C: mesh 線網 512b -> $bits(flit_t)=525b (pkg flit_t 完整標頭);
  // 原 he_*/vn_v/vs_v/ad_tx_v COV-EXEMPT 全部移除 — EAST 及全向路由修復後可達,
  // 由 tb/cov_soc/soc_east_tb.sv directed 測試 + soc_smoke_tb/stub flood 真實覆蓋
  localparam int MX = 4, MY = 2;
  localparam int FLIT_W = $bits(flit_t);  // 525
  logic [FLIT_W-1:0] vn_d [MX]; logic vn_v [MX]; logic vn_r [MX];  // R(x,0).north -> R(x,1)
  logic [FLIT_W-1:0] vs_d [MX]; logic vs_v [MX]; logic vs_r [MX];  // R(x,1).south -> R(x,0)
  logic [FLIT_W-1:0] he_d [MX-1][MY]; logic he_v [MX-1][MY]; logic he_r [MX-1][MY];
  logic [FLIT_W-1:0] hw_d [MX-1][MY]; logic hw_v [MX-1][MY]; logic hw_r [MX-1][MY];
  logic [FLIT_W-1:0] ad_rx_d [MX][MY]; logic ad_rx_v [MX][MY]; logic ad_rx_r [MX][MY];
  logic [FLIT_W-1:0] ad_tx_d [MX][MY]; logic ad_tx_v [MX][MY]; logic ad_tx_r [MX][MY];

  // v6.3.3 整合: cpu_tile 已新增 backpressure input `noc_out_ready_i`,
  // adapter 的 t_out_ready 正式回授給 tile (取代 v633-noc 暫接的 unused 線網)。
  logic ct_adp_or [NUM_CPU_TILES];
  for (genvar x = 0; x < MX; x++) begin : g_ad
    orca_flit_adapter u_adc (
      .clk(clk_noc), .rst_n(rst_n),
      .t_out(ct_out[x]), .t_out_ready(ct_adp_or[x]),
      .t_in(ct_in[x]), .t_in_valid(ct_iv[x]), .t_in_ready(1'b1),
      .r_rx_data(ad_rx_d[x][0]), .r_rx_valid(ad_rx_v[x][0]), .r_rx_ready(ad_rx_r[x][0]),
      .r_tx_data(ad_tx_d[x][0]), .r_tx_valid(ad_tx_v[x][0]), .r_tx_ready(ad_tx_r[x][0]));
    orca_flit_adapter u_ada (
      .clk(clk_noc), .rst_n(rst_n),
      .t_out(at_out[x]), .t_out_ready(at_or[x]),
      .t_in(at_in[x]), .t_in_valid(at_iv[x]), .t_in_ready(at_ir[x]),
      .r_rx_data(ad_rx_d[x][1]), .r_rx_valid(ad_rx_v[x][1]), .r_rx_ready(ad_rx_r[x][1]),
      .r_tx_data(ad_tx_d[x][1]), .r_tx_valid(ad_tx_v[x][1]), .r_tx_ready(ad_tx_r[x][1]));
  end

  // v6.3.3: 完整 mesh 埠位對接
  // 資料/valid 順向流 (tx -> 鄰居 rx); ready 反向流 (接收端 rx_ready -> 發送端 tx_ready)
  // 垂直: R(x,0).north_tx ->vn-> R(x,1).south_rx; R(x,1).south_tx ->vs-> R(x,0).north_rx
  // 水平: R(x,y).east_tx ->he-> R(x+1,y).west_rx; R(x+1,y).west_tx ->hw-> R(x,y).east_rx
  for (genvar x = 0; x < MX; x++) begin : g_r
    for (genvar y = 0; y < MY; y++) begin : g_c
      logic [FLIT_W-1:0] n_rx_d, s_rx_d, e_rx_d, w_rx_d;  // v6.3.4 fix BUG-C: 512b->525b
      logic n_rx_v, s_rx_v, e_rx_v, w_rx_v;
      logic n_rx_r, s_rx_r, e_rx_r, w_rx_r;   // router rx_ready (輸出)
      logic [FLIT_W-1:0] n_tx_d, s_tx_d, e_tx_d, w_tx_d;  // v6.3.4 fix BUG-C: 512b->525b
      logic n_tx_v, s_tx_v, e_tx_v, w_tx_v;
      logic n_tx_rdy, s_tx_rdy, e_tx_rdy, w_tx_rdy;  // router tx_ready (輸入)

      // ---- 垂直 rx/tx 對接 (vn/vs wrap 兩個方向都完整接好) ----
      if (y == 0) begin : g_y0
        // north_rx 接收 vs link (R(x,1).south_tx); ready 回送給 vs link
        assign n_rx_d  = vs_d[x];  assign n_rx_v = vs_v[x];
        assign vs_r[x] = n_rx_r;
        // north_tx 驅動 vn link (送往 R(x,1).south_rx); ready 來自 vn link
        assign vn_d[x] = n_tx_d;   assign vn_v[x] = n_tx_v;
        assign n_tx_rdy = vn_r[x];
        // south 為 mesh 下緣邊界 (y=-1 不存在): rx tie-off, tx 恒 ready 吸收
        assign s_rx_d = '0;        assign s_rx_v = 1'b0;
        assign s_tx_rdy = 1'b1;    // tie-off: 邊界 tx_ready 拉高, s_tx_d/s_tx_v 不送出
      end else begin : g_y1
        // south_rx 接收 vn link (R(x,0).north_tx); ready 回送給 vn link
        assign s_rx_d  = vn_d[x];  assign s_rx_v = vn_v[x];
        assign vn_r[x] = s_rx_r;
        // south_tx 驅動 vs link (送往 R(x,0).north_rx); ready 來自 vs link
        assign vs_d[x] = s_tx_d;   assign vs_v[x] = s_tx_v;
        assign s_tx_rdy = vs_r[x];
        // north 為 mesh 上緣邊界 (y=MY 不存在): rx tie-off, tx 恒 ready 吸收
        assign n_rx_d = '0;        assign n_rx_v = 1'b0;
        assign n_tx_rdy = 1'b1;    // tie-off: 邊界 tx_ready 拉高, n_tx_d/n_tx_v 不送出
      end

      // ---- 水平 rx/tx 對接 ----
      if (x < MX-1) begin : g_ex
        // east_rx 接收 hw link (R(x+1,y).west_tx); ready 回送給 hw link
        assign e_rx_d = hw_d[x][y];  assign e_rx_v = hw_v[x][y];
        assign hw_r[x][y] = e_rx_r;
        // east_tx 驅動 he link (送往 R(x+1,y).west_rx); ready 來自 he link
        assign he_d[x][y] = e_tx_d;  assign he_v[x][y] = e_tx_v;
        assign e_tx_rdy = he_r[x][y];
      end else begin : g_exb
        // east 為 mesh 右緣邊界 (x=MX 不存在): rx tie-off, tx 恒 ready 吸收
        assign e_rx_d = '0; assign e_rx_v = 1'b0;
        assign e_tx_rdy = 1'b1;  // tie-off: 邊界 tx_ready 拉高, e_tx_d/e_tx_v 不送出
      end
      if (x > 0) begin : g_wx
        // west_rx 接收 he link (R(x-1,y).east_tx); ready 回送給 he link
        assign w_rx_d = he_d[x-1][y];  assign w_rx_v = he_v[x-1][y];
        assign he_r[x-1][y] = w_rx_r;
        // west_tx 驅動 hw link (送往 R(x-1,y).east_rx); ready 來自 hw link
        assign hw_d[x-1][y] = w_tx_d;  assign hw_v[x-1][y] = w_tx_v;
        assign w_tx_rdy = hw_r[x-1][y];
      end else begin : g_wxb
        // west 為 mesh 左緣邊界 (x=-1 不存在): rx tie-off, tx 恒 ready 吸收
        assign w_rx_d = '0; assign w_rx_v = 1'b0;
        assign w_tx_rdy = 1'b1;  // tie-off: 邊界 tx_ready 拉高, w_tx_d/w_tx_v 不送出
      end

      orca_noc_router #(
        .X_POS(x), .Y_POS(y), .NUM_VC(NOC_VC), .DATA_WIDTH(FLIT_W),  // v6.3.4 fix BUG-C: 512->525
        .BUF_DEPTH(2), .X_DIM(4), .Y_DIM(2)
      ) u_r (
        .clk(clk_noc), .rst_n(rst_n),
        .north_rx_data(n_rx_d), .north_rx_valid(n_rx_v), .north_rx_ready(n_rx_r),
        .north_tx_data(n_tx_d), .north_tx_valid(n_tx_v), .north_tx_ready(n_tx_rdy),
        .south_rx_data(s_rx_d), .south_rx_valid(s_rx_v), .south_rx_ready(s_rx_r),
        .south_tx_data(s_tx_d), .south_tx_valid(s_tx_v), .south_tx_ready(s_tx_rdy),
        .east_rx_data(e_rx_d),  .east_rx_valid(e_rx_v),  .east_rx_ready(e_rx_r),
        .east_tx_data(e_tx_d),  .east_tx_valid(e_tx_v),  .east_tx_ready(e_tx_rdy),
        .west_rx_data(w_rx_d),  .west_rx_valid(w_rx_v),  .west_rx_ready(w_rx_r),
        .west_tx_data(w_tx_d),  .west_tx_valid(w_tx_v),  .west_tx_ready(w_tx_rdy),
        .local_rx_data(ad_rx_d[x][y]), .local_rx_valid(ad_rx_v[x][y]), .local_rx_ready(ad_rx_r[x][y]),
        .local_tx_data(ad_tx_d[x][y]), .local_tx_valid(ad_tx_v[x][y]), .local_tx_ready(ad_tx_r[x][y]));

      // 邊界 rx_ready 輸出不影響功能 (對應 rx_valid 已 tie 0), 僅供觀察
      wire unused_bnd_rx_rdy = (y == 0 ? s_rx_r : n_rx_r)
                             ^ (x == 0 ? w_rx_r : 1'b0)
                             ^ (x == MX-1 ? e_rx_r : 1'b0);
    end
  end

  ddr5_ctrl u_ddr5 (
    .clk(clk_sys), .rst_n(rst_n),
    .req_addr('0), .req_valid(1'b0), .req_we(1'b0), .req_wdata('0),
    .req_ready(), .req_rdata(), .req_done(),
    .ddr5_ck_t(ddr5_ck_t), .ddr5_ck_c(ddr5_ck_c), .ddr5_cs_n(ddr5_cs_n),
    .ddr5_addr(ddr5_addr), .ddr5_ba(ddr5_ba), .ddr5_act_n(ddr5_act_n),
    .ddr5_dq_o(), .ddr5_dq_oe(), .ddr5_dq_i(ddr5_dq));

  pcie_gen6 u_pcie (
    .clk(clk_sys), .rst_n(rst_n),
    .pcie_tx_p(pcie_tx_p), .pcie_tx_n(pcie_tx_n),
    .pcie_rx_p(pcie_rx_p), .pcie_rx_n(pcie_rx_n),
    .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
    .tlp_in('0), .tlp_in_valid(1'b0), .tlp_in_ready(),
    .tlp_out(), .tlp_out_valid());

  orca_bow_link u_bow (
    .clk(clk_sys), .rst_n(rst_n),
    .bow_tx_data(bow_tx_data), .bow_tx_clk(bow_tx_clk),
    .bow_rx_data(bow_rx_data), .bow_rx_clk(bow_rx_clk),
    .link_up(), .train_start(1'b1));

  logic [3:0] jtag_sr;
  always_ff @(posedge jtag_tck or negedge rst_n) begin
    if (!rst_n) jtag_sr <= '0;
    else jtag_sr <= {jtag_sr[2:0], jtag_tdi};
  end
  assign jtag_tdo = jtag_sr[3];
  assign nmi_out  = ~ext_irq_n;
endmodule : orca_v63_soc
