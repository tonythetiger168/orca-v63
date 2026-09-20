// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.4
`include "orca_pkg.sv"

// flit_t <-> orca_noc_router 介面卡
// v6.3.4 fix BUG-C: 退化為直通 — 全鏈路統一 orca_pkg::flit_t (525b 線網),
// 每個 flit (含 BODY/TAIL) 自帶完整標頭進出線網, 不再做 v6.3.3 的 512b 私有
// 編碼 (head flit 截斷 payload[495:0]、body/tail 無標頭), 根除 adapter↔router
// 位元錯位 (router dest_x 恆讀 0 → EAST 不可達) 之根因。
module orca_flit_adapter
  import orca_pkg::*; (
  input  logic clk, rst_n,
  // tile side (flit_t)
  input  flit_t t_out,
  output logic t_out_ready,
  output flit_t t_in,
  output logic  t_in_valid,
  input  logic  t_in_ready,
  // router side (flit_t 線網, $bits(flit_t) = 525b)
  output logic [$bits(flit_t)-1:0] r_rx_data,
  output logic                     r_rx_valid,
  input  logic                     r_rx_ready,
  input  logic [$bits(flit_t)-1:0] r_tx_data,
  input  logic                     r_tx_valid,
  output logic                     r_tx_ready
);
  // 直通: pkg flit_t 完整標頭上線, valid/ready 一對一對接
  assign r_rx_data   = t_out;
  assign r_rx_valid  = t_out.valid;
  assign t_out_ready = r_rx_ready;
  always_comb begin
    t_in       = flit_t'(r_tx_data);
    t_in.valid = r_tx_valid;   // 以線網握手 valid 為準 (無授權時 tx_flit='0)
  end
  assign t_in_valid = r_tx_valid;
  assign r_tx_ready = t_in_ready;
  // clk/rst_n 保留以維持介面層次 (直通無時序邏輯)
  wire unused_clk_rst = clk ^ rst_n;
endmodule : orca_flit_adapter
