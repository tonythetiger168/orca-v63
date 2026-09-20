// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// L1D 包裝: dcache + MSHR 介面 + store buffer 直通
module lsu_dcache
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  paddr_t    req_addr,
  input  logic      req_valid,
  input  logic      req_we,
  input  xword_t    req_wdata,
  input  logic [7:0] req_wmask,
  output logic      req_ready,
  output xword_t    req_rdata,
  output logic      req_hit,
  output paddr_t    miss_addr,
  output logic      miss_valid,
  input  logic      miss_ack,
  input  logic [511:0] fill_line,
  input  logic      fill_valid,
  output logic      wb_valid,
  output paddr_t    wb_addr,
  output logic [511:0] wb_line,
  output logic      stbuf_empty
);
  import orca_pkg::*;
  logic hit;
  xword_t rdata;
  assign req_hit   = hit;
  assign req_rdata = rdata;
  assign req_ready = hit || miss_ack;
  assign stbuf_empty = 1'b1;
  dcache u_dcache (
    .clk(clk), .rst_n(rst_n),
    .req_addr(req_addr), .req_valid(req_valid), .req_ready(),
    .hit(hit), .req_rdata(rdata),
    .req_wdata(req_wdata), .req_wmask(req_we ? req_wmask : 8'h0),
    .miss_addr(miss_addr), .miss_valid(miss_valid), .miss_ack(miss_ack),
    .fill_line(fill_line), .fill_valid(fill_valid), .fill_dirty(1'b0),
    .wb_valid(wb_valid), .wb_addr(wb_addr), .wb_line(wb_line));
endmodule : lsu_dcache
