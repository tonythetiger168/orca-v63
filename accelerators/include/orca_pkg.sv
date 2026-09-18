`ifndef ORCA_PKG_SV
`define ORCA_PKG_SV
`include "orca_params.sv"
package orca_pkg;
  typedef struct packed {
    logic valid; logic ready; logic stall; logic flush; logic bubble;
  } pipe_ctrl_t;
  typedef struct packed {
    logic [63:0] pc; logic [31:0] inst; logic valid; logic pred_taken;
    logic [63:0] pred_target; logic [6:0] rob_id; logic [1:0] priv;
  } fetch_pkt_t;
  typedef struct packed {
    logic valid; logic [63:0] pc; logic [31:0] inst; logic [6:0] opcode;
    logic [2:0] funct3; logic [6:0] funct7; logic [4:0] rs1, rs2, rd;
    logic [63:0] imm; logic [2:0] fu_type; logic [3:0] lsu_op;
    logic use_rs1, use_rs2, use_rd, is_branch, is_jump, is_csr, is_fence, is_amo;
    logic ecall, ebreak, mret, sret, uret; logic [6:0] rob_id, prd, prs1, prs2, lprd;
    logic [1:0] priv;
  } decode_pkt_t;
  typedef struct packed {
    logic valid; logic [63:0] pc, result, result_hi, branch_target;
    logic branch_taken, mispredict; logic [6:0] rob_id, prd;
    logic [4:0] rd; logic rd_write; logic [2:0] fu_type; logic [3:0] lsu_op;
    logic [63:0] lsu_addr, lsu_wdata; logic [7:0] lsu_wmask; logic lsu_req;
    logic exception; logic [4:0] exc_code; logic [63:0] exc_tval; logic [1:0] priv;
  } exec_pkt_t;
  typedef struct packed {
    logic valid; logic [6:0] rob_id, prd; logic [4:0] rd; logic rd_write;
    logic [3:0] lsu_op; logic [63:0] addr, wdata; logic [7:0] wmask, rdata;
    logic is_amo; logic [3:0] amo_op; logic is_fence, is_fencei;
    logic exception; logic [4:0] exc_code; logic [63:0] exc_tval; logic [1:0] priv;
  } lsu_pkt_t;
  typedef struct packed {
    logic valid; logic [6:0] rob_id, prd; logic [4:0] rd;
    logic [63:0] wdata; logic rd_write; logic exception;
    logic [4:0] exc_code; logic [63:0] exc_tval; logic [1:0] priv;
  } wb_pkt_t;
  typedef struct packed {
    logic valid; logic [6:0] rob_id, prd, lprd; logic [4:0] rd;
    logic [63:0] pc; logic rd_write; logic exception; logic [4:0] exc_code;
    logic [63:0] exc_tval; logic is_branch, branch_taken;
    logic [63:0] branch_target; logic mispredict, is_amo, is_fence, is_fencei;
    logic [1:0] priv;
  } commit_pkt_t;
  typedef struct packed {
    logic valid; logic [63:0] addr; logic [2:0] size; logic we;
    logic [63:0] wdata; logic [7:0] wmask; logic [3:0] id;
    logic cacheable; logic [2:0] prot;
  } mem_req_t;
  typedef struct packed {
    logic valid; logic [63:0] rdata; logic [3:0] id; logic err;
  } mem_resp_t;
  typedef struct packed {
    logic valid; logic [63:0] vaddr; logic [1:0] priv; logic we;
  } tlb_req_t;
  typedef struct packed {
    logic valid; logic [63:0] paddr; logic hit, page_fault, access_fault;
    logic [2:0] prot;
  } tlb_resp_t;
  typedef struct packed {
    logic valid; logic [6:0] prd; logic [63:0] data;
  } fwd_t;
  typedef struct packed {
    logic valid, complete, exception; logic [4:0] exc_code;
    logic [63:0] exc_tval, pc; logic [6:0] prd, lprd;
    logic [4:0] rd; logic rd_write, is_branch, branch_taken;
    logic [63:0] branch_target; logic mispredict; logic [2:0] fu_type;
    logic [63:0] result; logic [1:0] priv;
  } rob_entry_t;
  typedef struct packed {
    logic valid, ready, completed; logic [6:0] rob_id, prd;
    logic [4:0] rd; logic rd_write; logic [3:0] lsu_op;
    logic [63:0] addr, wdata; logic [7:0] wmask, rdata;
    logic is_amo; logic [3:0] amo_op; logic is_fence, is_fencei;
    logic exception; logic [4:0] exc_code; logic [63:0] exc_tval; logic [1:0] priv;
  } lsq_entry_t;
endpackage
`endif
