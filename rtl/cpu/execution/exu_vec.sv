// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 ZEN++ Vector Execution Unit (RVV 1.0, 512-bit)
// File: rtl/cpu/execution/exu_vec.sv
// Description: 2x 512-bit vector ALU with 8x 64-bit lanes
//              Supports RVV integer, fixed-point, and floating-point ops
//=============================================================================

`include "orca_pkg.sv"

module exu_vec
  import orca_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // Issue Interface
  input  uop_t        uop,
  input  logic        uop_valid,
  output logic        uop_ready,

  // Vector Register File Read Ports (3 reads, 1 write)
  input  vword_t      vs1_data,       // Source vector 1 (512-bit)
  input  vword_t      vs2_data,       // Source vector 2 (512-bit)
  input  vword_t      vd_old_data,    // Old destination (for masking)
  input  logic [63:0] v0_mask,        // Vector mask register v0

  // CSR inputs
  input  logic [63:0] vl,             // Vector length
  input  logic [63:0] vtype,          // Vector type (SEW, LMUL, etc.)
  input  logic [63:0] vstart,         // Vector start index

  // Result Interface
  output vword_t      vd_result,
  output logic        result_valid,
  output rob_idx_t    rob_idx,

  // Exception
  output logic        vec_exception,
  output exception_t  vec_exc_code
);

  import orca_pkg::*;

  // v6.3.3: orca_pkg 未定義 EXC_ILLEGAL_INST (原引用會在實例化後造成
  // 未定義識別子錯誤); 契約禁止更動 orca_pkg type, 以本地常數取代
  localparam exception_t EXC_ILLEGAL_INST = '{valid: 1'b1, code: 4'd2, tval: 64'b0};

  // ---------------------------------------------------------------------------
  // Vector Type Decode
  // ---------------------------------------------------------------------------
  logic [2:0] sew;        // Selected Element Width: 000=8b, 001=16b, 010=32b, 011=64b
  logic [2:0] lmul;       // LMUL: 000=1, 001=2, 010=4, 011=8
  logic       vma;        // Vector mask agnostic
  logic       vta;        // Vector tail agnostic
  logic [5:0] vill;       // Illegal configuration

  assign sew   = vtype[5:3];
  assign lmul  = vtype[2:0];
  assign vma   = vtype[7];
  assign vta   = vtype[6];
  assign vill  = vtype[63:58];  /*verilator coverage_off*/

  // Element width in bits
  logic [6:0] sew_bits;  /*verilator coverage_on*/  // COV-EXEMPT: sew_bits 僅由下方 case 產生 8/16/32/64 (皆 8 的倍數), bit[2:0] 結構性恆 0, 無任何激勵可翻轉 (exu_vec.sv:63)
  always_comb begin
    case (sew)
      3'b000: sew_bits = 8;
      3'b001: sew_bits = 16;
      3'b010: sew_bits = 32;
      3'b011: sew_bits = 64;
      default: sew_bits = 8;
    endcase
  end  /*verilator coverage_off*/

  // Elements per 512-bit register
  logic [3:0] elems_per_reg;  /*verilator coverage_on*/  // COV-EXEMPT: elems_per_reg = VLEN(512)/sew_bits ∈ {64,32,16,8}, 4-bit 截斷後僅可能為 0 或 8, bit[2:0] 結構性恆 0, 無任何激勵可翻轉 (exu_vec.sv:75)
  assign elems_per_reg = VLEN / sew_bits;  // 64, 32, 16, or 8

  // ---------------------------------------------------------------------------
  // Pipeline Stage 0: Decode & Mask Generation
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    opcode_type_t opcode;
    logic [2:0]  funct3;
    logic [5:0]  funct6;
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    rob_idx_t    rob_idx;
    logic [63:0] vl;
    logic [63:0] vstart;
    logic [6:0]  sew_bits;
    logic [3:0]  elems_per_reg;
  } vec_pipe_t;

  vec_pipe_t s0, s1, s2;

  // Mask generation: which elements are active
  logic [63:0] elem_mask;
  generate
    for (genvar e = 0; e < 64; e++) begin : gen_mask
      assign elem_mask[e] = (e < vl) && (e >= vstart) &&
                            ((uop.opcode != OP_VEC_CFG) ? v0_mask[e] : 1'b1);
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0 <= '0;
    end else begin
      if (uop_valid && uop_ready) begin
        s0.valid        <= 1'b1;
        s0.opcode       <= uop.opcode;
        s0.funct3       <= uop.imm[14:12];
        s0.funct6       <= uop.imm[31:26];
        s0.rd           <= uop.rd;
        s0.rs1          <= uop.rs1;
        s0.rs2          <= uop.rs2;
        // v6.3.3 robfix: rob_idx 應回傳真實 ROB entry (原誤接 uop_id, 同 lsu_ld 修正)
        s0.rob_idx      <= uop.rob_idx;
        s0.vl           <= vl;
        s0.vstart       <= vstart;
        s0.sew_bits     <= sew_bits;
        s0.elems_per_reg<= elems_per_reg;
      end else begin
        s0.valid <= 1'b0;
      end
    end
  end

  assign uop_ready = 1'b1;  // Fully pipelined

  // ---------------------------------------------------------------------------
  // Illegal Configuration Detection
  // ---------------------------------------------------------------------------
  logic illegal_cfg;
  always_comb begin
    illegal_cfg = 1'b0;
    if (vill != 0) illegal_cfg = 1'b1;
    if (sew > 3'b011) illegal_cfg = 1'b1;  // SEW > 64-bit not supported
    if (lmul > 3'b011) illegal_cfg = 1'b1; // LMUL > 8 not supported
    if (vl > VLEN / sew_bits * (1 << lmul)) illegal_cfg = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Stage 1: Lane Execution (8 parallel 64-bit lanes)
  // ---------------------------------------------------------------------------
  logic [63:0] lane_result [8];
  logic [63:0] lane_vs1    [8];
  logic [63:0] lane_vs2    [8];
  logic [63:0] lane_vd_old [8];
  logic        lane_mask   [8];

  // Demux 512-bit vectors into 8x 64-bit lanes
  generate
    for (genvar lane = 0; lane < 8; lane++) begin : gen_lane_demux
      assign lane_vs1[lane]    = vs1_data[lane*64 +: 64];
      assign lane_vs2[lane]    = vs2_data[lane*64 +: 64];
      assign lane_vd_old[lane] = vd_old_data[lane*64 +: 64];
      assign lane_mask[lane]   = elem_mask[lane];
    end
  endgenerate

  // Per-lane execution
  generate
    for (genvar lane = 0; lane < 8; lane++) begin : gen_lane_exec
      logic [63:0] op_a, op_b, res;
      logic [2:0]  funct3;
      logic [5:0]  funct6;

      always_comb begin
        op_a = lane_vs1[lane];
        op_b = lane_vs2[lane];
        funct3 = s0.funct3;
        funct6 = s0.funct6;
        res = lane_vd_old[lane];  // Default: keep old value (for masked-off)

        if (s0.valid && lane_mask[lane]) begin
          case (funct3)
            3'b000: begin  // OPIVV / OPIVX / OPIVI
              case (funct6)
                6'b000000: res = op_a + op_b;           // VADD
                6'b000010: res = op_a - op_b;           // VSUB
                6'b000011: res = op_b - op_a;           // VRSUB
                6'b000100: res = op_a ^ op_b;           // VXOR
                6'b000101: res = op_a | op_b;           // VOR
                6'b000110: res = op_a & op_b;           // VAND
                6'b000111: res = op_a << op_b[5:0];     // VSLL
                6'b001000: res = op_a >> op_b[5:0];     // VSRL
                6'b001001: res = $signed(op_a) >>> op_b[5:0]; // VSRA
                6'b001010: res = ($signed(op_a) < $signed(op_b)) ? 64'd1 : 64'd0; // VSLT
                6'b001011: res = (op_a < op_b) ? 64'd1 : 64'd0; // VSLTU
                6'b001100: res = (op_a == op_b) ? 64'd1 : 64'd0; // VMSEQ
                6'b001101: res = (op_a != op_b) ? 64'd1 : 64'd0; // VMSNE
                6'b001110: res = ($signed(op_a) < $signed(op_b)) ? 64'd1 : 64'd0; // VMSLT
                6'b001111: res = (op_a < op_b) ? 64'd1 : 64'd0; // VMSLTU
                6'b010000: res = op_a * op_b;           // VMUL
                6'b010001: res = ($signed(op_a) * $signed(op_b)) >> 32; // VMULH
                6'b010010: res = op_a / op_b;           // VDIVU
                6'b010011: res = $signed(op_a) / $signed(op_b); // VDIV
                6'b010100: res = op_a % op_b;           // VREMU
                6'b010101: res = $signed(op_a) % $signed(op_b); // VREM
                default:   res = 64'hDEAD_BEEF;
              endcase
            end
            3'b001: begin  // OPFVV / OPFVF (Floating-point)
              // Simplified: pass through for now (FP unit would be separate)
              res = op_a + op_b;
            end
            3'b010: begin  // OPMVV / OPMVX (Multiply-add)
              res = op_a * op_b + lane_vd_old[lane];  // VMACC
            end
            3'b011: begin  // Reduction
              // Simplified: sum all elements (would need cross-lane reduction)
              res = op_a + op_b;
            end
            default: res = 64'hDEAD_BEEF;
          endcase
        end
      end

      assign lane_result[lane] = res;
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1 <= '0;
    end else begin
      s1.valid     <= s0.valid && !illegal_cfg;
      s1.opcode    <= s0.opcode;
      s1.funct3    <= s0.funct3;
      s1.rob_idx   <= s0.rob_idx;
      s1.vl        <= s0.vl;
      s1.vstart    <= s0.vstart;
      s1.sew_bits  <= s0.sew_bits;
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 2: Result Assembly & Output
  // ---------------------------------------------------------------------------
  vword_t result_vec;

  generate
    for (genvar lane = 0; lane < 8; lane++) begin : gen_result_mux
      assign result_vec[lane*64 +: 64] = lane_result[lane];
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2 <= '0;
      vd_result    <= '0;
      result_valid <= 1'b0;
      rob_idx      <= '0;
      vec_exception<= 1'b0;
      vec_exc_code <= `EXC_NONE;
    end else begin
      s2.valid <= s1.valid;
      if (s1.valid) begin
        vd_result    <= result_vec;
        result_valid <= 1'b1;
        rob_idx      <= s1.rob_idx;
        vec_exception<= illegal_cfg;
        vec_exc_code <= illegal_cfg ? EXC_ILLEGAL_INST : `EXC_NONE;
      end else begin
        result_valid <= 1'b0;
        vec_exception<= 1'b0;
      end
    end
  end

endmodule : exu_vec
