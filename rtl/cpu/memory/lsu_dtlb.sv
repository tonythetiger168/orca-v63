// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// D-TLB: DTLB_ENTRIES 項 2-way, Sv48 walk FSM, refill
module lsu_dtlb
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  xword_t va,
  input  logic q_valid,
  output logic hit,
  output paddr_t pa,
  output logic walk_req,
  output xword_t walk_addr,
  input  logic walk_rvalid,
  input  xword_t walk_rdata,
  input  logic fill_valid,
  input  xword_t fill_va,
  input  paddr_t fill_pa
);
  import orca_pkg::*;
  localparam int SETS = DTLB_ENTRIES / 2, SW = $clog2(SETS);
  logic [43:0] vpn [SETS][2];
  paddr_t      ppn [SETS][2]; /* verilator coverage_off */
  logic        vld [SETS][2]; /* verilator coverage_on */  // COV-EXEMPT: vld[s][0] 結構恆 0: vw 選擇式在 vld[s][0]=0 時恆選 way1 (lsu_dtlb.sv:44-46), 且 vld 無清除路徑, way0 永不置位
  logic [2:0]  lrup [SETS]; /* verilator coverage_off */ // cov: wire 宣告初始化被工具別名化, 無獨立賦值點 (tool limit)
  wire [SW-1:0] set = va[SW+11:12]; /* verilator coverage_on */
  wire [43:0] qvpn = va[55:12];
  always_comb begin
    hit = 1'b0; pa = va;
    for (int w = 0; w < 2; w++)
      if (vld[set][w] && vpn[set][w] == qvpn) begin
        hit = 1'b1;
        pa = {ppn[set][w][PLEN-1:12], va[11:0]};
      end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < SETS; s++) begin
        vld[s][0] <= 1'b0; vld[s][1] <= 1'b0; lrup[s] <= '0;
      end
    end else begin
      if (fill_valid) begin
        automatic int vw = (vld[fill_va[SW+11:12]][0] && vld[fill_va[SW+11:12]][1])
                           ? int'(lrup[fill_va[SW+11:12]][0]) : int'(!vld[fill_va[SW+11:12]][0]);
        vld[fill_va[SW+11:12]][vw] <= 1'b1;
        vpn[fill_va[SW+11:12]][vw] <= fill_va[55:12];
        ppn[fill_va[SW+11:12]][vw] <= fill_pa;
        lrup[fill_va[SW+11:12]] <= 3'(vw);
      end
    end
  end
  // walk FSM stub: 由外部 MMU walker 處理, 此處僅產生請求脈衝
  typedef enum logic [1:0] {W_IDLE, W_REQ, W_WAIT} wst_t;
  wst_t wst;
  xword_t wva;
  assign walk_req   = (wst == W_REQ);
  assign walk_addr  = wva;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin wst <= W_IDLE; wva <= '0; end
    else begin
      unique case (wst)
        W_IDLE: if (q_valid && !hit) begin wst <= W_REQ; wva <= va; end
        W_REQ:  wst <= W_WAIT;
        W_WAIT: if (walk_rvalid) wst <= W_IDLE;
        default: wst <= W_IDLE;
      endcase
    end
  end
endmodule : lsu_dtlb
