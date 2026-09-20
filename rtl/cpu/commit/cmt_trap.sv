// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 異常處理: retire 例外優先編碼, per-thread flush, 最小 CSR
module cmt_trap
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  exception_t [RETIRE_WIDTH-1:0] rt_exc,
  input  tid_t [RETIRE_WIDTH-1:0] rt_tid,
  input  xword_t [RETIRE_WIDTH-1:0] rt_pc,
  input  logic [RETIRE_WIDTH-1:0] rt_valid,
  output logic trap_valid,
  output tid_t trap_tid,
  output xword_t trap_pc,
  output logic [3:0] trap_cause,
  output xword_t trap_tval,
  output xword_t trap_vector,
  output logic [SMT_THREADS-1:0] flush_mask,
  input  logic csr_we,
  input  logic [11:0] csr_addr,
  input  xword_t csr_wdata,
  output xword_t csr_rdata
);
  import orca_pkg::*;
  xword_t csr_mtvec, csr_mstatus;
  xword_t csr_mepc [SMT_THREADS], csr_mcause [SMT_THREADS];
  int sel;
  always_comb begin
    sel = -1;
    for (int i = RETIRE_WIDTH - 1; i >= 0; i--)
      if (rt_valid[i] && rt_exc[i].valid) sel = i;
    trap_valid  = (sel >= 0);
    trap_tid    = (sel >= 0) ? rt_tid[sel] : tid_t'(0);
    trap_pc     = (sel >= 0) ? rt_pc[sel] : '0;
    trap_cause  = (sel >= 0) ? rt_exc[sel].code : 4'h0;
    trap_tval   = (sel >= 0) ? rt_exc[sel].tval : '0;
    trap_vector = csr_mtvec;
    flush_mask  = '0;
    if (trap_valid) flush_mask[trap_tid] = 1'b1;
    unique case (csr_addr)
      12'h305: csr_rdata = csr_mtvec;
      12'h341: csr_rdata = csr_mepc[trap_tid];
      12'h342: csr_rdata = csr_mcause[trap_tid];
      12'h300: csr_rdata = csr_mstatus;
      default: csr_rdata = '0;
    endcase
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      csr_mtvec <= '0; csr_mstatus <= 64'h8;
      for (int t = 0; t < SMT_THREADS; t++) begin
        csr_mepc[t] <= '0; csr_mcause[t] <= '0;
      end
    end else begin
      if (csr_we) begin
        unique case (csr_addr)
          12'h305: csr_mtvec <= csr_wdata;
          12'h300: csr_mstatus <= csr_wdata;
          default: ;
        endcase
      end
      if (trap_valid) begin
        csr_mepc[trap_tid]   <= trap_pc;
        csr_mcause[trap_tid] <= {60'b0, trap_cause};
        csr_mstatus[3]       <= 1'b0;
      end
    end
  end
endmodule : cmt_trap
