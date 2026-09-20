// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// DMA 引擎: HBM3<->L2 64B beat 傳輸, descriptor 長度驅動
module npu_dma
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  aix_cmd_t desc,
  input  logic   desc_valid,
  output logic   desc_ready,
  output logic   done,
  output logic [31:0] l2_addr,
  output logic        l2_req,
  input  logic [511:0] l2_rdata,
  output logic [511:0] l2_wdata,
  output logic        l2_we,
  output paddr_t hbm_addr,
  output logic   hbm_req,
  output logic   hbm_we,
  input  logic [511:0] hbm_rdata,
  output logic [511:0] hbm_wdata,
  input  logic   hbm_ack
);
  import orca_pkg::*;
  typedef enum logic [1:0] {D_IDLE, D_XFER, D_LAST} dst_t;
  dst_t st;
  xword_t cnt, len;
  wire is_ld = (desc.opcode == AIX_OP_DMA_LD);
  assign desc_ready = (st == D_IDLE);
  assign l2_addr    = {16'b0, desc.tdb0, 16'b0};
  assign l2_we      = is_ld;
  assign l2_wdata   = hbm_rdata;
  assign l2_req     = (st == D_XFER);
  assign hbm_addr   = {16'h0, desc.tdb1, 32'h0};
  assign hbm_we     = is_ld;
  assign hbm_wdata  = l2_rdata;
  assign hbm_req    = (st == D_XFER);
  assign done       = (st == D_LAST);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= D_IDLE; cnt <= '0; len <= '0; end
    else begin
      unique case (st)
        D_IDLE: if (desc_valid) begin
          len <= {32'b0, desc.length}; cnt <= '0; st <= D_XFER;
        end
        D_XFER: if (hbm_ack) begin
          cnt <= cnt + 64;
          if (cnt + 64 >= len) st <= D_LAST;
        end
        D_LAST: st <= D_IDLE;
        default: st <= D_IDLE;
      endcase
    end
  end
endmodule : npu_dma
