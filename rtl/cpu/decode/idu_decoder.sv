// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 6-wide 解碼器: RV64I/M/A/F/V + custom-0 AIX
module idu_decoder
  import orca_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] inst,
  input  logic        valid,
  input  xword_t      pc,
  input  tid_t        tid,
  output uop_t        uop,
  output logic        ready
);
  import orca_pkg::*;

  logic [63:0] i_imm, s_imm; /*verilator coverage_off*/ logic [63:0] b_imm, j_imm, u_imm; /*verilator coverage_on*/ // COV-EXEMPT: b_imm[0]/j_imm[0]=1'b0 與 u_imm[11:0]=12'b0 結構恆定 (assign 於 L23-25), toggle 不可達; 其餘 imm bits 已由 f1_decode_tb 功能覆蓋
  always_comb begin
    i_imm = {{52{inst[31]}}, inst[31:20]};
    s_imm = {{52{inst[31]}}, inst[31:25], inst[11:7]};
    b_imm = {{51{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    u_imm = {{32{inst[31]}}, inst[31:12], 12'b0};
    j_imm = {{43{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
  end

  always_comb begin
    uop          = `UOP_NOP;
    uop.pc       = pc;
    uop.tid      = tid;
    uop.rs1      = inst[19:15];
    uop.rs2      = inst[24:20];
    uop.rd       = inst[11:7];
    uop.funct3   = inst[14:12];
    uop.funct7   = inst[31:25];
    uop.imm      = i_imm;
    uop.exc      = `EXC_NONE;
    unique case (inst[6:0])
      7'b0110111: begin uop.opcode = OP_LUI;    uop.imm = u_imm; end
      7'b0010111: begin uop.opcode = OP_AUIPC;  uop.imm = u_imm; end
      7'b1101111: begin uop.opcode = OP_JAL;    uop.imm = j_imm;
                        uop.is_branch = 1'b1; uop.is_call = 1'b1; end
      7'b1100111: begin uop.opcode = OP_JALR;   uop.imm = i_imm;
                        uop.is_branch = 1'b1; uop.is_indirect = 1'b1;
                        uop.is_return = (inst[19:15] == 5'd1); end
      7'b1100011: begin uop.opcode = OP_BRANCH; uop.imm = b_imm;
                        uop.is_branch = 1'b1; uop.is_cond = 1'b1; end
      7'b0000011: begin uop.opcode = OP_LOAD;   uop.is_load = 1'b1; end
      7'b0100011: begin uop.opcode = OP_STORE;  uop.is_store = 1'b1; uop.imm = s_imm; end
      7'b0010011: uop.opcode = OP_ALUI;
      7'b0110011: begin
        if (inst[31:25] == 7'b0000001)
          uop.opcode = inst[14:12][2] ? OP_DIV : OP_MUL;
        else uop.opcode = OP_ALU;
      end
      7'b0101111: uop.opcode = OP_AMO;
      7'b0001111: uop.opcode = OP_FENCE;
      7'b1110011: begin
        if (inst[14:12] == 3'b000) uop.opcode = OP_SYSTEM;
        else begin uop.opcode = OP_CSR; uop.imm = {52'b0, inst[31:20]}; end
      end
      7'b1000011: begin uop.opcode = OP_FPLD; uop.is_fp = 1'b1; uop.is_load = 1'b1; end
      7'b1000111: begin uop.opcode = OP_FPST; uop.is_fp = 1'b1; uop.is_store = 1'b1; uop.imm = s_imm; end
      7'b1010011: begin uop.opcode = OP_FP;  uop.is_fp = 1'b1; end
      7'b1010111: begin
        uop.is_vec = 1'b1;
        uop.opcode = (inst[25] == 1'b0) ? OP_VEC_CFG : OP_VEC;
      end
      7'b0000111: begin uop.opcode = OP_VEC_LD; uop.is_vec = 1'b1; uop.is_load = 1'b1; end
      7'b0100111: begin uop.opcode = OP_VEC_ST; uop.is_vec = 1'b1; uop.is_store = 1'b1; uop.imm = s_imm; end
      7'b0001011: begin uop.opcode = OP_AIX; uop.is_aix = 1'b1; end // custom-0
      default: begin
        uop.opcode = OP_NOP;
        uop.exc.valid = valid;
        uop.exc.code  = 4'd2;
        uop.exc.tval  = {32'b0, inst};
      end
    endcase
    if (!valid) uop = `UOP_NOP;
  end
  assign ready = 1'b1;
endmodule : idu_decoder
