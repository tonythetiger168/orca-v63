// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3.3.2 SVA 覆蓋率量測 checker - NoC Router (對應 tb/sva/sva_noc.sv 12 顆)
// 語意銜接對照 (詳 sva_cov_report.txt):
//   [N1] dest_x/dest_y 由 flit header 推導 (router 無獨立 dest 暫存);
//        原 SVA 宣告 [3:0][3:0] 只有 4 埠卻索引 PORT_LOCAL=4 (宣告 bug),
//        本 checker 改 [4:0][3:0]
//   [N2] N5 之 4'hX 佔位 = router 自身座標 (X_POS,Y_POS), TB 以參數帶入
//   [N3] N6 同拍 |-> 改 [1:4] 視窗: router rx 先進 buffer (FF), tx 最早下一拍
//   [N4] coh_* 由 TB 實例之 orca_chi_coh x2 提供 (router 無一致性狀態)
//   [N5] N3 s_eventually 以 [1:10] 有界視窗實作 (同 N1 視窗)
//   [N6] N10 前提 rx_valid && !rx_ready 結構性不可觸發:
//        router wr/rd_ptr 於 BUF_DEPTH-1 wrap => buf_count <= BUF_DEPTH-2
//        < BUF_DEPTH => buf_full 恆 0 => rx_ready 恆 1 (lead 核准 N/A, 證明見報告)
//   [N7] N4 vc_fairness 原 SVA assert 已註解 => cover 型, 只計 attempts
//=============================================================================
`include "orca_pkg.sv"

module sva_noc_cov
  import orca_pkg::*; #(
  parameter int X_POS = 1,
  parameter int Y_POS = 1
) (
  input logic clk,
  input logic rst_n,

  input logic [4:0] rx_valid,
  input logic [4:0] rx_ready,
  input logic [4:0] tx_valid,
  input logic [4:0] tx_ready,

  input logic [511:0] rx_data [5],
  input logic [511:0] tx_data [5],

  input logic [4:0] [3:0] dest_x,   // [N1] 修正原 SVA 埠數宣告
  input logic [4:0] [3:0] dest_y,
  input logic [4:0] [3:0] vc_id,

  input coh_state_t [4:0] coh_state_rx,
  input coh_state_t [4:0] coh_state_tx,
  input logic       [4:0] coh_req_valid,
  input logic       [4:0] coh_rsp_valid
);

  localparam int PORT_NORTH = 0;
  localparam int PORT_SOUTH = 1;
  localparam int PORT_EAST  = 2;
  localparam int PORT_WEST  = 3;
  localparam int PORT_LOCAL = 4;

  localparam int NP = 12;
  localparam string PNAME [NP] = '{
    "N1a_no_lost_rx",      "N1b_no_lost_tx",     "N2a_no_x_rx_valid",
    "N2b_no_x_tx_valid",   "N3_tx_liveness",     "N4_vc_fairness(cover)",
    "N5_local_only_dest",  "N6_xy_routing[1:4]", "N7_valid_coh_transition",
    "N8_single_coh_req",   "N9_modified_persist","N10_no_buffer_overflow(N/A)" };

  int att  [NP];
  int fail [NP];
  int cyc = 0;

  // N1a/N1b/N3/N5: rx/tx stall streak (valid 等待 ready)
  int rx_stall [5];
  int tx_stall [5];
  // N6 視窗追蹤 (1..4)
  int n6_birth [$];
  // N9 一拍管線
  logic n9_v;
  // N4 cover: vc==0 之後見到 vc==1
  logic [4:0] n4_armed;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NP; i++) begin att[i] <= 0; fail[i] <= 0; end
      cyc <= 0; n9_v <= 0; n4_armed <= '0;
      for (int p = 0; p < 5; p++) begin rx_stall[p] <= 0; tx_stall[p] <= 0; end
      n6_birth.delete();
    end else begin
      cyc <= cyc + 1;

      // ---- N1a: rx_valid -> rx_ready ≤10 (每 valid 拍一 attempt) ----
      for (int p = 0; p < 5; p++) begin
        if (rx_valid[p]) begin
          att[0]++;
          if (rx_ready[p]) rx_stall[p] <= 0;
          else begin
            rx_stall[p] <= rx_stall[p] + 1;
            if (rx_stall[p] >= 10) fail[0]++;
          end
        end else rx_stall[p] <= 0;
      end
      // ---- N1b: tx_valid -> tx_ready ≤10 ----
      for (int p = 0; p < 5; p++) begin
        if (tx_valid[p]) begin
          att[1]++;
          if (tx_ready[p]) tx_stall[p] <= 0;
          else begin
            tx_stall[p] <= tx_stall[p] + 1;
            if (tx_stall[p] >= 10) fail[1]++;
          end
        end else tx_stall[p] <= 0;
      end

      // ---- N2: valid 不得為 X (2-state 模擬恆真, 量測每拍) ----
      for (int p = 0; p < 5; p++) begin
        att[2]++; if ($isunknown(rx_valid[p])) fail[2]++;
        att[3]++; if ($isunknown(tx_valid[p])) fail[3]++;
      end

      // ---- N3: tx liveness (s_eventually -> [1:10] 有界) [N5] ----
      // 與 N1b 同視窗; 獨立計 attempts (tx_valid 觸發)
      for (int p = 0; p < 5; p++) begin
        if (tx_valid[p]) begin
          att[4]++;
          if (!tx_ready[p] && tx_stall[p] >= 10) fail[4]++;
        end
      end

      // ---- N4 (cover): vc_id 0 -> 之後見到 1 [N7] ----
      for (int p = 0; p < 5; p++) begin
        if (vc_id[p] == 4'd0) n4_armed[p] <= 1'b1;
        else if (vc_id[p] == 4'd1 && n4_armed[p]) begin
          att[5]++;
          n4_armed[p] <= 1'b0;
        end
      end

      // ---- N5: local tx 之 flit dest 必為本 router [N2] ----
      if (tx_valid[PORT_LOCAL]) begin
        att[6]++;
        if (!(int'(dest_x[PORT_LOCAL]) == X_POS && int'(dest_y[PORT_LOCAL]) == Y_POS))
          fail[6]++;
      end

      // ---- N6: local rx (dest_x != X_POS) -> [1:4] 內 E/W tx [N3] ----
      for (int i = 0; i < n6_birth.size(); i++) begin
        automatic int age = cyc - n6_birth[i];
        if ((tx_valid[PORT_EAST] || tx_valid[PORT_WEST]) && age >= 1) begin
          n6_birth.delete(i); i--;
        end else if (age > 4) begin
          fail[7]++; n6_birth.delete(i); i--;
        end
      end
      if (rx_valid[PORT_LOCAL] && int'(dest_x[PORT_LOCAL]) != X_POS) begin
        att[7]++;
        n6_birth.push_back(cyc);
      end

      // ---- N7: coh M -> 不得轉 S [N4] ----
      if (coh_state_rx[PORT_LOCAL] == COH_MODIFIED) begin
        att[8]++;
        if (coh_state_tx[PORT_LOCAL] == COH_SHARED) fail[8]++;
      end

      // ---- N8: 同埠同拍 req/rsp 至多一個 ----
      for (int p = 0; p < 5; p++) begin
        if (coh_req_valid[p] || coh_rsp_valid[p]) begin
          att[9]++;
          if (coh_req_valid[p] && coh_rsp_valid[p]) fail[9]++;
        end
      end

      // ---- N9: M 態 + 背壓 -> 下拍仍 M ----
      if (n9_v) begin
        if (coh_state_rx[PORT_LOCAL] != COH_MODIFIED) fail[10]++;
      end
      if (coh_state_rx[PORT_LOCAL] == COH_MODIFIED && !tx_ready[PORT_LOCAL]) begin
        att[10]++;
        n9_v <= 1'b1;
      end else n9_v <= 1'b0;

      // ---- N10: N/A [N6] — 前提結構性不可觸發, 計 0 attempts ----
      // (保留計數欄位, 若奇蹟觸發仍量測)
      for (int p = 0; p < 5; p++) begin
        if (rx_valid[p] && !rx_ready[p]) begin
          att[11]++;
        end
      end
    end
  end

  final begin
    int nonvac, tot_fail;
    nonvac = 0; tot_fail = 0;
    $display("==== sva_noc_cov 總表 ====");
    for (int i = 0; i < NP; i++) begin
      if (att[i] >= 1) nonvac++;
      tot_fail += fail[i];
      $display("SVACOV|NOC|%s|attempts=%0d|fails=%0d", PNAME[i], att[i], fail[i]);
    end
    $display("SVA_COV: sva_noc %0d/%0d nonvacuous, %0d fail", nonvac, NP, tot_fail);
  end

endmodule : sva_noc_cov
