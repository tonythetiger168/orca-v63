// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// CHI 一致性代理: 請求處理, MESI-F 狀態轉換, snoop 回應
package orca_chi_pkg;
  typedef enum logic [2:0] {CHI_RD, CHI_WR, CHI_RDO, CHI_WRO, CHI_EVICT} chi_req_op_t;
endpackage

module orca_chi_coh
  import orca_pkg::*;
  import orca_chi_pkg::*;
(
  input  logic clk, rst_n,
  input  paddr_t req_addr,
  input  logic   req_valid,
  input  chi_req_op_t req_op,
  output logic   req_ready,
  output logic [511:0] rsp_data,
  output logic   rsp_valid,
  input  paddr_t snp_addr,
  input  logic   snp_valid,
  output coh_state_t snp_state,
  output logic   snp_dirty,
  output logic [511:0] snp_data,
  output logic   snp_ack
);
  import orca_pkg::*;
  coh_state_t state;
  logic [511:0] data_buf;
  assign req_ready  = 1'b1;
  assign rsp_valid  = req_valid;
  assign rsp_data   = data_buf;
  assign snp_state  = state;
  assign snp_dirty  = (state == COH_MODIFIED);
  assign snp_data   = data_buf;
  assign snp_ack    = snp_valid;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin state <= COH_INVALID; data_buf <= '0; end
    else begin
      if (req_valid) begin
        unique case (req_op)
          CHI_RD:        state <= COH_SHARED;
          CHI_RDO:       state <= COH_EXCLUSIVE;
          CHI_WR, CHI_WRO: state <= COH_MODIFIED;
          CHI_EVICT:     state <= COH_INVALID;
          default: ;
        endcase
      end
      if (snp_valid && state != COH_MODIFIED) state <= COH_SHARED;
    end
  end
endmodule : orca_chi_coh
