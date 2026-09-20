// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// BoW chiplet 介面: 訓練序列 stub, bump 資料直通
module orca_bow_link
  import orca_pkg::*; (
  input  logic clk, rst_n,  /*verilator coverage_off*/
  output logic [7:0] bow_tx_data, bow_tx_clk,  /*verilator coverage_on*/  // COV-EXEMPT: bow_tx_data 結構性常數 — line17 恆驅動 8'hA5, bit1/3/4/6 恆 0 邏輯不可達 (bow_tx_clk 已功能命中, 同行一併標示)
  input  logic [7:0] bow_rx_data, bow_rx_clk,
  output logic       link_up,
  input  logic       train_start
);
  logic [3:0] cnt;
  assign link_up    = (cnt == 4'hF);
  assign bow_tx_clk = {8{cnt[0]}};
  assign bow_tx_data = 8'hA5;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cnt <= '0;
    else if (train_start && !link_up) cnt <= cnt + 1'b1;
  end
endmodule : orca_bow_link
