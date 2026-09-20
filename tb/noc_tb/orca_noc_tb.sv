// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"

// NoC smoke test: flit 傳送延遲檢查
module orca_noc_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  flit_t tx, rx;
  logic txv, txr, rxv, rxr;
  logic [15:0] phy_tx; logic phy_tx_v;
  assign phy_rx_v = phy_tx_v;   // external loopback for smoke test
  logic [15:0] phy_rx;
  assign phy_rx = phy_tx;
  orca_noc_link u_link (
    .clk(clk), .rst_n(rst_n),
    .tx_flit(tx), .tx_valid(txv), .tx_ready(txr),
    .rx_flit(rx), .rx_valid(rxv), .rx_ready(rxr),
    .phy_tx(phy_tx), .phy_tx_v(phy_tx_v), .phy_rx(phy_rx), .phy_rx_v(phy_rx_v),
    .link_up(), .rx_credit({NOC_VC{1'b1}}));

  int lat = 0;
  initial begin
    tx = '0; txv = 0; rxr = 1;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    tx.valid    = 1'b1;
    tx.ftype    = FLIT_SINGLE;
    tx.dest_x   = 2'd3;
    tx.dest_y   = 2'd3;
    tx.payload  = 512'hDEAD_BEEF;
    txv = 1'b1;
    @(negedge clk); txv = 1'b0;
    while (!rxv && lat < 100) begin @(negedge clk); lat = lat + 1; end
    if (lat > 20) $fatal(1, "TB FAIL: link latency %0d", lat);
    $display("TB PASS: flit received, latency %0d clk", lat);
    $finish;
  end
endmodule : orca_noc_tb
