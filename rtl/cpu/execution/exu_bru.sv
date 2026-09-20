// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 分支解析: 實際走向 vs BPU 預測, 產生 redirect
module exu_bru
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t uop,
  input  logic uop_valid,
  output logic uop_ready,
  input  xword_t operand_a, operand_b,
  output logic redirect_valid,
  output xword_t redirect_pc,
  output rob_idx_t rob_idx,
  output logic mispredict,
  output logic bpu_update_valid,
  output xword_t bpu_update_pc,
  output logic bpu_update_taken,
  output xword_t bpu_update_target
);
  import orca_pkg::*;
  logic cond, taken;
  xword_t tgt;
  always_comb begin
    case (uop.funct3)
      3'b000:  cond = (operand_a == operand_b);
      3'b001:  cond = (operand_a != operand_b);
      3'b100:  cond = ($signed(operand_a) <  $signed(operand_b));
      3'b101:  cond = ($signed(operand_a) >= $signed(operand_b));
      3'b110:  cond = (operand_a <  operand_b);
      3'b111:  cond = (operand_a >= operand_b);
      default: cond = 1'b0;
    endcase
    taken = uop.is_cond ? cond : 1'b1;
    tgt   = (uop.opcode == OP_JALR) ? ({operand_a[63:1], 1'b0} + uop.imm)
                                    : (uop.pc + uop.imm);
  end
  assign uop_ready  = 1'b1;
  assign rob_idx    = uop.rob_idx;
  assign mispredict = uop_valid && ((taken != uop.pred_taken)
                      || (taken && (tgt != uop.pred_target)));
  assign redirect_valid = uop_valid && mispredict;
  assign redirect_pc    = taken ? tgt : uop.pc + 4;
  assign bpu_update_valid = uop_valid && uop.is_branch;
  assign bpu_update_pc    = uop.pc;
  assign bpu_update_taken = taken;
  assign bpu_update_target= tgt;
endmodule : exu_bru
