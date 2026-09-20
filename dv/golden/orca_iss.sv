// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - 內嵌黃金參考 ISS (RV64IM): 從 uop 語義欄位執行, 鏡像架構暫存器 x0-x31。
// async-lockstep 比對的核心: 每條 in-order retire 指令, ISS 讀自身 x[] 計算期望值,
// 與 RTL retire result 比對, 再更新自身 x[rd]。支援 DPI-Spike 無需安裝的離線 smoke 流程;
// 生產流程以 Spike 經 DPI 替換本模組 (介面相同)。
`include "orca_pkg.sv"

module orca_iss
  import orca_pkg::*;
(
  input  logic clk, rst_n,
  input  logic        retire_valid,   // in-order retire (ROB 依序)
  input  opcode_type_t opcode,
  input  logic [2:0]  funct3,
  input  logic [4:0]  rs1a, rs2a, rda,
  input  xword_t      imm,
  input  xword_t      rt_result,      // RTL 實際結果 (待比對)
  input  xword_t      rt_pc,
  output logic        mismatch,       // 1 = 黃金 vs RTL 不一致
  output xword_t      exp_result,     // ISS 期望值
  output logic [4:0]  dbg_rda
);
  import orca_pkg::*;
  xword_t x [32];                      // 鏡像架構暫存器 (x0 恆 0)
  xword_t a, b, exp;
  logic   mm;

  assign exp_result = exp;
  assign dbg_rda = rda;

  always_comb begin
    a = x[rs1a];  b = x[rs2a];  exp = rt_result;  mm = 1'b0;
    if (retire_valid) begin
      unique case (opcode)
        OP_ALU, OP_ALUI: begin
          unique case (funct3)
            3'd0:  exp = (opcode == OP_ALU && imm[5]) ? a - b : a + b;  // SUB 由 imm[5](=funct7[5]) 區分
            3'd1:  exp = a << b[5:0];
            3'd2:  exp = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
            3'd3:  exp = (a < b) ? 64'd1 : 64'd0;
            3'd4:  exp = a ^ b;
            3'd5:  exp = imm[5] ? $signed(a) >>> b[5:0] : a >> b[5:0];
            3'd6:  exp = a | b;
            3'd7:  exp = a & b;
          endcase
        end
        OP_LUI:   exp = imm;
        OP_AUIPC: exp = rt_pc + imm;
        OP_MUL:  exp = a * b;
        OP_DIV:  exp = (b == 0) ? {64{1'b1}} : (a == 64'h8000_0000_0000_0000 && b == 64'hFFFF_FFFF_FFFF_FFFF) ? a : $signed(a) / $signed(b);
        default:  exp = rt_result;   // 其餘型態 (load/store/branch) 由專用比對略過
      endcase
      // 比對 (rd=x0 不檢查; load/store/branch 不比對 rd 值)
      if (rda != 0 && !(opcode inside {OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_JALR, OP_FENCE}))
        mm = (exp !== rt_result);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) x[i] <= '0;
      mismatch <= 1'b0;
    end else begin
      mismatch <= mm;
      if (retire_valid && rda != 0 && !(opcode inside {OP_LOAD, OP_STORE, OP_BRANCH, OP_FENCE}))
        x[rda] <= exp;
    end
  end
endmodule : orca_iss
