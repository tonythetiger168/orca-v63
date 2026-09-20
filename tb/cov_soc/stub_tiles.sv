// SPDX-License-Identifier: Apache-2.0
// stub_tiles.sv: SoC 頂層覆蓋專用之空殼 tile (port 相容, 內部.tie-off)
// 理由: 3GB 機型無法同時 elaborate 4×cpu_tile + 4×ai_tile + coverage;
//       cpu_tile/ai_tile 內部行已由 f1_cpu_tile_tb / f4_ai_tile_tb 等 100% 覆蓋,
//       此處僅需觸發 orca_v63_soc.sv 本身之 mesh 佈線/邊界 tie-off/JTAG 行。
`include "orca_pkg.sv"

module orca_v63_cpu_tile
  import orca_pkg::*;
#(
  parameter int TILE_ID = 0,
  parameter int NCO = CORES_PER_CPU_TILE
)(
  input  logic clk, rst_n,
  output flit_t noc_out,
  input  flit_t noc_in,
  output logic  noc_out_ready,
  input  logic  noc_in_valid,
  input  logic [7:0] irq_lines,
  output logic irq_ack,
  input  logic  noc_out_ready_i
);
  logic [7:0] cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cnt <= '0; noc_out <= '0; noc_out_ready <= 1'b0; irq_ack <= 1'b0; end
    else begin
      logic [511:0] pl;
      cnt <= cnt + 8'd1 + TILE_ID[7:0];
      // 發出合法 single flit: 目的 = AI row (x,1), 使北向垂直鏈路翻轉
      // 注意: orca_noc_router 使用私有 flit_t 解線網, vc_id 位於 wire[491:488]
      // (= pkg payload[491:488]); 必須填入 0~3 否則 flit 寫入越界 VC 被丟棄。
      pl = {64{cnt}} ^ noc_in.payload;
      pl[495:492] = cnt[3:0];   // msg_type (任意, 保持翻轉)
      pl[491:488] = cnt[1:0];   // router vc_id ∈ 0..3
      pl[487:476] = {4{cnt[2:0]}};  // packet_id
      pl[475:468] = cnt;        // router flit_type (router 路由不檢查, 保持翻轉)
      noc_out.payload <= pl;
      noc_out.dest_x  <= NOC_X_BITS'((TILE_ID == 3) ? 0 : TILE_ID + 1);  // 對角: 觸發東/西向路由
      noc_out.dest_y  <= NOC_Y_BITS'(1);
      noc_out.src_x   <= NOC_X_BITS'(TILE_ID);
      noc_out.src_y   <= '0;
      noc_out.vc_id   <= '0;
      noc_out.ftype   <= FLIT_SINGLE;
      noc_out.valid   <= cnt[0];
      noc_out_ready   <= cnt[1];
      irq_ack         <= ^irq_lines;
    end
  end
endmodule : orca_v63_cpu_tile

module orca_v63_ai_tile
  import orca_pkg::*;
#(
  parameter int TILE_ID = 0,
  parameter int NCLUSTERS = CLUSTERS_PER_TILE
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
  output logic  hbm_init_done
);
  logic [7:0] cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= '0; noc_out <= '0; aix_ready <= 1'b0; noc_in_ready <= 1'b0;
      aix_irq <= 1'b0; hbm_ck_t <= '0; hbm_ck_c <= '1; hbm_cs_n <= '1; hbm_init_done <= 1'b0;
    end else begin
      logic [511:0] pl;
      cnt <= cnt + 8'd3 + TILE_ID[7:0];
      // 發出合法 single flit: 目的 = CPU row (x,0), 使南向鏈路翻轉
      // v6.3.4 fix BUG-C: 說明同 cpu_tile stub — 標頭寫 struct 欄位, 無魔法位元
      pl = {64{cnt}} ^ noc_in.payload;
      noc_out.payload <= pl;
      noc_out.dest_x  <= NOC_X_BITS'((TILE_ID == 3) ? 0 : TILE_ID + 1);  // 對角: 觸發東/西向路由
      noc_out.dest_y  <= '0;
      noc_out.src_x   <= NOC_X_BITS'(TILE_ID);
      noc_out.src_y   <= NOC_Y_BITS'(1);
      noc_out.vc_id   <= cnt[1:0];   // v6.3.4 fix BUG-C: vc_id 0..3 放標頭位
      noc_out.ftype   <= FLIT_SINGLE;
      noc_out.valid   <= cnt[1];
      aix_ready    <= cnt[1] & aix_valid;
      noc_in_ready <= cnt[2] | ~noc_in_valid;
      aix_irq      <= cnt[7];
      hbm_ck_t     <= {HBM3_STACKS{cnt[0]}};
      hbm_ck_c     <= {HBM3_STACKS{~cnt[0]}};
      hbm_cs_n     <= {HBM3_STACKS{cnt[3]}};
      hbm_init_done<= 1'b1;
    end
  end
endmodule : orca_v63_ai_tile
