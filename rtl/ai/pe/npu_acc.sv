// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 累加/活化單元: bias + ReLU/GELU(一階近似) + 量化
module npu_acc
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  logic [31:0] acc_in,
  input  logic        in_valid,
  input  logic [31:0] bias,
  input  logic [3:0]  dtype,
  input  logic [1:0]  act_mode,     // 0=linear 1=ReLU 2=GELU 3=reserved
  output logic [7:0]  out,
  output logic        out_valid
);
  import orca_pkg::*;
  logic [31:0] s0, s1;
  wire signed [32:0] sum    = $signed({acc_in[31], acc_in}) + $signed({bias[31], bias});
  wire [31:0]        biased = sum[32] ? 32'h0 : sum[31:0];
  wire signed [31:0] g      = $signed(biased);
  wire signed [63:0] g3     = g * g * g;
  wire signed [31:0] gelu   = g + g3 / 32'sd400;   // GELU 一階 tanh 近似
  wire [31:0] act = (act_mode == 2'd1) ? biased :
                    (act_mode == 2'd2) ? ((g < -32'sd3000) ? 32'h0
                                        : 32'((gelu >>> 1) + (g >>> 1))) : biased;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; out <= '0; s0 <= '0; s1 <= '0; end
    else begin
      s0 <= act; s1 <= s0;
      out_valid <= in_valid;
      unique case (dtype)
        AI_DTYPE_INT8:                 out <= s1[7:0];
        AI_DTYPE_INT2:                 out <= {6'b0, s1[1:0]};
        AI_DTYPE_INT3:                 out <= {5'b0, s1[2:0]};
        AI_DTYPE_INT4,
        AI_DTYPE_NF4,
        AI_DTYPE_FP4:                  out <= {4'b0, s1[3:0]};   // 4-bit packed output
        AI_DTYPE_INT5:                 out <= {3'b0, s1[4:0]};
        AI_DTYPE_INT6:                 out <= {2'b0, s1[5:0]};
        AI_DTYPE_BITNET:               out <= s1[7:0];           // BitNet: activation stays 8-bit
        AI_DTYPE_FP8_E4M3,
        AI_DTYPE_FP8_E5M2,
        AI_DTYPE_BF8:                  out <= s1[7:0];           // 8-bit float output
        default:                       out <= s1[15:8];          // BF16/FP16 high byte
      endcase
    end
  end
endmodule : npu_acc
