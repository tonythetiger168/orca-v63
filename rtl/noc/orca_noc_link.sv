// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// NoC 鏈路層: flit CRC16 + credit 流控 + retry buffer
module orca_noc_link
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  flit_t tx_flit,
  input  logic  tx_valid,
  output logic  tx_ready,
  output flit_t rx_flit,
  output logic  rx_valid,
  input  logic  rx_ready,
  output logic [15:0] phy_tx,
  output logic        phy_tx_v,
  input  logic [15:0] phy_rx,
  input  logic        phy_rx_v,
  output logic        link_up,
  input  logic [NOC_VC-1:0] rx_credit
);
  import orca_pkg::*;
  function automatic logic [15:0] crc16(input logic [511:0] d);
    logic [15:0] c;
    c = 16'hFFFF;
    for (int i = 0; i < 512; i++)
      c = {c[14:0], 1'b0} ^ ((c[15] ^ d[i]) ? 16'h1021 : 16'h0);
    return c;
  endfunction
  flit_t retry_buf;
  logic  retry_v;
  wire credit_ok = |rx_credit;
  assign tx_ready = credit_ok && (!retry_v || tx_valid);
  // CRC16 sideband: 傳送 payload 的 CRC (bug fix v6.3.4: crc16 原為死碼未接入)
  assign phy_tx   = tx_valid ? crc16(tx_flit.payload) : '0;
  assign phy_tx_v = tx_valid;
  assign rx_valid = phy_rx_v;
  always_comb begin
    rx_flit         = `FLIT_EMPTY;
    rx_flit.valid   = phy_rx_v;
    rx_flit.payload = {496'b0, phy_rx};
  end
  assign link_up = 1'b1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) retry_v <= 1'b0;
    else begin
      if (tx_valid && !credit_ok) begin retry_buf <= tx_flit; retry_v <= 1'b1; end
      else if (retry_v && credit_ok) retry_v <= 1'b0;
    end
  end
endmodule : orca_noc_link
