// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// AI Tile NoC 介面卡: DMA 請求打包 flit, credit 流控
module npu_tile_noc
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  paddr_t  dma_addr,
  input  logic    dma_valid,
  input  logic    dma_is_write,
  input  logic [511:0] dma_wdata,
  output logic    dma_ready,
  output logic [511:0] dma_rdata,
  output flit_t   noc_out,
  input  logic    noc_out_ready,
  input  flit_t   noc_in,
  input  logic    noc_in_valid,
  output logic    noc_in_ready,
  input  logic [NOC_VC-1:0] vc_credit
);
  import orca_pkg::*;
  typedef enum logic [1:0] {N_IDLE, N_HDR, N_PAY, N_RSP} nst_t;
  nst_t st;
  wire credit_ok = vc_credit[0];
  assign dma_ready    = (st == N_IDLE);
  assign noc_in_ready = (st == N_RSP);
  assign dma_rdata    = noc_in.payload;
  always_comb begin
    // v6.3.4 fix BUG-C: HEAD 與 TAIL 兩拍均帶完整 pkg flit_t 標頭 (dest/vc/ftype),
    // 配合 orca_flit_adapter 直通化, TAIL 不再以 raw payload 上線 (舊 adapter 對
    // body/tail 送無標頭 raw 資料導致 router 誤路由); 此處標頭欄位對兩 state 皆生效
    noc_out = `FLIT_EMPTY;
    noc_out.valid = (st == N_HDR) || (st == N_PAY);
    noc_out.ftype = (st == N_HDR) ? FLIT_HEAD : FLIT_TAIL;
    noc_out.dest_x = NOC_X_BITS'(dma_addr[9:8]);
    noc_out.dest_y = 2'b00;
    noc_out.vc_id  = 2'b00;
    noc_out.payload = (st == N_HDR) ? {dma_addr, 448'b0} : dma_wdata;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) st <= N_IDLE;
    else begin
      unique case (st)
        N_IDLE: if (dma_valid) st <= N_HDR;
        N_HDR:  if (noc_out_ready && credit_ok) st <= N_PAY;
        N_PAY:  if (noc_out_ready && credit_ok) st <= N_RSP;
        N_RSP:  if (noc_in_valid) st <= N_IDLE;  /*verilator coverage_off*/ // default arm 邏輯不可達 (enum 全狀態已列)
        default: st <= N_IDLE;  /*verilator coverage_on*/
      endcase
    end
  end
endmodule : npu_tile_noc
