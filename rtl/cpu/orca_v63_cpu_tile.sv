// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.3
`include "orca_pkg.sv"


// CPU Tile: 8×ZEN++ 核心 + L2 + L3 + NoC flit 介面
// v6.3.3: 新增 input port noc_out_ready_i (NoC 對 cpu_tile 送出方向的
//         backpressure 回授, 供 NoC agent 的 flit adapter t_out_ready 使用)
module orca_v63_cpu_tile
  import orca_pkg::*;
#(
  parameter int TILE_ID = 0,
  parameter int NCO = CORES_PER_CPU_TILE   // lint override only
)(
  input  logic clk, rst_n,
  output flit_t noc_out,
  input  flit_t noc_in,
  output logic  noc_out_ready,
  input  logic  noc_in_valid,
  input  logic [7:0] irq_lines,
  output logic irq_ack,
  // v6.3.3 (新增 port): NoC 下游對 noc_out 的 ready 回授 (backpressure)
  input  logic  noc_out_ready_i
);
  import orca_pkg::*;
  paddr_t l2_addr [NCO];
  logic   l2_v    [NCO];
  logic [511:0] l2_line;
  logic  l2_fill_v;
  logic  halt_all;

  genvar c;
  generate
    for (c = 0; c < NCO; c++) begin : g_core
      orca_v63_cpu_core u_core (
        .clk(clk), .rst_n(rst_n), .tid(tid_t'(c % SMT_THREADS)),
        .l2_req_addr(l2_addr[c]), .l2_req_valid(l2_v[c]),
        .l2_fill_line(l2_line), .l2_fill_valid(l2_fill_v),
        .core_halt(halt_all));
    end
  endgenerate

  l2cache u_l2 (
    .clk(clk), .rst_n(rst_n),
    .req_addr(l2_addr[0]), .req_valid(l2_v[0]), .req_ready(),
    .hit(), .req_rdata(), .req_wdata('0), .req_wmask('0),
    .miss_addr(), .miss_valid(), .miss_ack(1'b0),
    .fill_line('0), .fill_valid(1'b0), .fill_dirty(1'b0),
    .wb_valid(), .wb_addr(), .wb_line());

  l3cache u_l3 (
    .clk(clk), .rst_n(rst_n),
    .req_addr('0), .req_valid(1'b0), .req_ready(),
    .hit(), .req_rdata(), .req_wdata('0), .req_wmask('0),
    .miss_addr(), .miss_valid(), .miss_ack(1'b0),
    .fill_line('0), .fill_valid(1'b0), .fill_dirty(1'b0),
    .wb_valid(), .wb_addr(), .wb_line());

  assign noc_out = `FLIT_EMPTY;
  assign noc_out_ready = 1'b1;
  assign irq_ack = |irq_lines;

  // v6.3.3: NoC backpressure 回授路徑。cpu_core 目前尚無 NoC 送出口
  // (noc_out 暫 tie FLIT_EMPTY), 此處先把 ready 收下並以 noc_out 全 0
  // (valid=0) 保證無有效 flit 被 backpressure; 待核心 NoC 介面落地後
  // 應將 noc_out_ready_i 接到核心送出 valid 的閘控。
  // TODO(v6.3.4): core NoC TX valid gating with noc_out_ready_i
  logic noc_out_ready_unused;
  assign noc_out_ready_unused = noc_out_ready_i;
endmodule : orca_v63_cpu_tile
