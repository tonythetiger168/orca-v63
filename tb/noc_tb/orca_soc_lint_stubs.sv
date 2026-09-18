// ORCA v6.3 ZEN++ - v6.3.3
`include "orca_pkg.sv"

// soc+noc 子集 lint 專用 stub (僅供 Workstream B lint, 不用於綜合/模擬)
// Workstream A (cpu) 與 C (ai) 並行開發中, 其 tile 內部不在本 lint 範圍;
// 此 stub 只保留 v6.3.2 baseline 的對外 port 契約, 驗證 SoC 層 NoC 連接。
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
  input  logic  noc_out_ready_i,   // v6.3.3 整合: 與真實 cpu_tile port 同步
  input  logic [7:0] irq_lines,
  output logic irq_ack
);
  // stub: NoC 端無流量, 僅完成 port 對接檢查
  assign noc_out       = `FLIT_EMPTY;
  assign noc_out_ready = 1'b1;
  assign irq_ack       = |irq_lines;
  wire unused = &{1'b0, clk, rst_n, noc_in, noc_in_valid, noc_out_ready_i, TILE_ID, NCO};
endmodule : orca_v63_cpu_tile

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
  output logic [HBM3_STACKS-1:0] hbm_ck_t, hbm_ck_c, hbm_cs_n
);
  // stub: NoC 端無流量, hbm pin 拉低, 僅完成 port 對接檢查
  assign aix_ready    = 1'b1;
  assign noc_out      = `FLIT_EMPTY;
  assign noc_in_ready = 1'b1;
  assign aix_irq      = 1'b0;
  assign hbm_ck_t     = '0;
  assign hbm_ck_c     = '0;
  assign hbm_cs_n     = '0;
  wire unused = &{1'b0, clk, rst_n, aix_uop, aix_valid, noc_out_ready,
                  noc_in, noc_in_valid, TILE_ID, NCLUSTERS};
endmodule : orca_v63_ai_tile
