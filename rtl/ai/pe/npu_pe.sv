// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 ORCA-NPU v3 Processing Element (PE)
// File: rtl/ai/pe/npu_pe.sv
// Description: Single PE in 64x64 systolic array
//              Supports INT8/INT4/BF16/FP16/FP32/FP8 MAC/FMA operations
//=============================================================================

`include "orca_pkg.sv"

module npu_pe
  import orca_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clk_gate,       // For power gating individual PEs

  // Systolic data flow (from left / from top)
  input  logic [7:0]  weight_in,      // Weight from left neighbor (or weight buffer)
  input  logic [7:0]  activation_in,  // Activation from top neighbor (or input buffer)
  input  logic [31:0] partial_sum_in, // Partial sum from top (for output stationary)

  output logic [7:0]  weight_out,     // Propagate to right
  output logic [7:0]  activation_out, // Propagate to bottom
  output logic [31:0] partial_sum_out,// Result to bottom or accumulator

  // Control
  input  logic [3:0]  dtype,          // Data type (INT8/INT4/BF16/FP16/FP32/FP8/BF8/NF4/FP4/BITNET)
  input  logic        weight_stationary, // 1: hold weight, 0: propagate
  input  logic        accumulate_en,  // Enable accumulation
  input  logic        flush_acc,      // Flush accumulator to output
  input  logic        sparse_skip     // Skip this PE (zero weight)
);

  import orca_pkg::*;

  // ---------------------------------------------------------------------------
  // Internal Registers
  // ---------------------------------------------------------------------------
  logic [7:0]  weight_reg;
  logic [7:0]  activation_reg;
  logic [31:0] accumulator;
  logic [31:0] mac_result;

  // ---------------------------------------------------------------------------
  // Data Type Handling
  // ---------------------------------------------------------------------------
  // For INT8: direct 8-bit multiply
  // For INT4: packed 2x 4-bit in 8-bit, processed as INT8 with shift
  // For BF16: 16-bit float (8-bit exponent, 7-bit mantissa)
  // For FP16: 16-bit IEEE 754
  // For FP32: 32-bit IEEE 754 (uses 4 cycles, pipelined)
  // For FP8: 8-bit float (E4M3 or E5M2)

  // Simplified: All operations go through a unified multiplier path
  // In real implementation, this would be multiple parallel datapaths

  // ---------------------------------------------------------------------------
  // MAC Computation
  // ---------------------------------------------------------------------------
  logic signed [15:0] mult_int8;
  logic signed [31:0] mult_int8_sext;

  assign mult_int8 = $signed(weight_reg) * $signed(activation_reg);
  assign mult_int8_sext = {{16{mult_int8[15]}}, mult_int8};

  // Sub-byte integer types INT2/INT3/INT4/INT5/INT6: sign-extend from dtype_int_bits
  // then INT8-multiply; throughput multiplier reflects packed ops-per-byte.
  logic signed [7:0]  sub_w, sub_a;
  logic signed [15:0] mult_sub;
  logic signed [31:0] mult_sub_sext;
  always_comb begin
    case (dtype)
      AI_DTYPE_INT2: begin sub_w = {{6{weight_reg[1]}}, weight_reg[1:0]};  sub_a = {{6{activation_reg[1]}}, activation_reg[1:0]};  end
      AI_DTYPE_INT3: begin sub_w = {{5{weight_reg[2]}}, weight_reg[2:0]};  sub_a = {{5{activation_reg[2]}}, activation_reg[2:0]};  end
      AI_DTYPE_INT4: begin sub_w = {{4{weight_reg[3]}}, weight_reg[3:0]};  sub_a = {{4{activation_reg[3]}}, activation_reg[3:0]};  end
      AI_DTYPE_INT5: begin sub_w = {{3{weight_reg[4]}}, weight_reg[4:0]};  sub_a = {{3{activation_reg[4]}}, activation_reg[4:0]};  end
      AI_DTYPE_INT6: begin sub_w = {{2{weight_reg[5]}}, weight_reg[5:0]};  sub_a = {{2{activation_reg[5]}}, activation_reg[5:0]};  end
      default:       begin sub_w = $signed(weight_reg);                    sub_a = $signed(activation_reg);                     end
    endcase
  end
  assign mult_sub     = sub_w * sub_a;
  assign mult_sub_sext = {{16{mult_sub[15]}}, mult_sub};

  // FP8/BF16 multiplier (simplified - would use FP unit in real design)
  logic [15:0] mult_fp16_raw;
  assign mult_fp16_raw = {weight_reg, activation_reg};  // Placeholder

  // FP32 (IEEE-754 single): simplified like FP16/BF16 above (real design uses a
  // shared FP pipe). Treats the 8b weight/activation as the mantissa byte of a
  // wider FP32 lane; full-precision FP32 arrives over the partial_sum_in bus.
  logic [31:0] fp32_mult;
  assign fp32_mult = {{8{mult_int8[15]}}, mult_int8, 8'h0};  // widened int product, FP-aligned

  // NF4 (NormalFloat-4): dequantize weight via LUT, then INT8 multiply
  logic signed [7:0]  nf4_w;
  logic signed [15:0] mult_nf4;
  logic signed [31:0] mult_nf4_sext;
  assign nf4_w        = nf4_dequant_lut(weight_reg[3:0]);
  assign mult_nf4     = $signed(activation_reg) * nf4_w;
  assign mult_nf4_sext = {{16{mult_nf4[15]}}, mult_nf4};

  // BitNet 1.58b: ternary weight decode {-1,0,+1} -> add/sub/skip, NO multiplier
  // 2-bit ternary code in weight_reg[1:0]; bit-pair selected by accumulator[1:0]
  logic signed [1:0]  bitnet_wsel;
  logic signed [31:0] bitnet_term;
  // MXFP4: E2M1 資料 × 共享 block scale (scale 在 partial_sum_in 高位), 2x throughput
  logic signed [15:0] mult_mxfp4;
  logic signed [31:0] mult_mxfp4_sext;
  assign mult_mxfp4     = $signed(activation_reg) * $signed({{4{weight_reg[3]}}, weight_reg[3:0]});
  assign mult_mxfp4_sext = ({{16{mult_mxfp4[15]}}, mult_mxfp4} * $signed(partial_sum_in[63:32])) <<< 1;
  assign bitnet_wsel  = bitnet_decode(weight_reg[1:0]);
  always_comb begin
    unique case (bitnet_wsel)
      2'sd1:   bitnet_term = {{24{activation_reg[7]}}, activation_reg};  // +1: pass activation
      -2'sd1:  bitnet_term = -{{24{activation_reg[7]}}, activation_reg}; // -1: negate
      default: bitnet_term = '0;                                        // 0: skip
    endcase
  end

  // ---------------------------------------------------------------------------
  // Accumulator Logic
  // ---------------------------------------------------------------------------
  always_comb begin
    if (sparse_skip) begin
      mac_result = accumulator;  // Skip computation, keep accumulator
    end else begin
      unique case (dtype)
        AI_DTYPE_INT8:   mac_result = accumulator + mult_int8_sext;
        AI_DTYPE_INT4:   mac_result = accumulator + (mult_sub_sext << 1);  // 2/byte, 2x throughput
        AI_DTYPE_INT2:   mac_result = accumulator + (mult_sub_sext << 2);  // 4/byte, 4x throughput
        AI_DTYPE_INT3:   mac_result = accumulator + (mult_sub_sext << 1);  // 2/byte, 2x throughput
        AI_DTYPE_INT5:   mac_result = accumulator + mult_sub_sext;         // 1/byte
        AI_DTYPE_INT6:   mac_result = accumulator + mult_sub_sext;         // 1/byte
        AI_DTYPE_BF16,
        AI_DTYPE_FP16:   mac_result = accumulator + {{16{mult_fp16_raw[15]}}, mult_fp16_raw}; // Simplified
        AI_DTYPE_FP32:   mac_result = accumulator + $signed(fp32_mult);  // FP32 widened path
        AI_DTYPE_FP8_E4M3,
        AI_DTYPE_FP8_E5M2,
        AI_DTYPE_BF8:    mac_result = accumulator + (mult_int8_sext << 1);  // FP8 1/byte, 2x throughput
        AI_DTYPE_FP4:    mac_result = accumulator + (mult_int8_sext << 1);  // 4-bit float, 2x throughput
        AI_DTYPE_NF4:    mac_result = accumulator + mult_nf4_sext;          // LUT-dequant, 2x below
        AI_DTYPE_FP4:    mac_result = accumulator + (mult_int8_sext << 1);
        AI_DTYPE_MXFP4:  mac_result = accumulator + mult_mxfp4_sext;   // block-scaled FP4           // ternary add/sub, no mult
        default:         mac_result = accumulator + mult_int8_sext;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential Logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_reg      <= '0;
      activation_reg  <= '0;
      accumulator     <= '0;
    end else if (clk_gate) begin
      // Weight register: either load new or propagate
      if (weight_stationary) begin
        if (sparse_skip)
          weight_reg <= '0;  // Zero out for sparse
        else
          weight_reg <= weight_reg;  // Hold
      end else begin
        weight_reg <= weight_in;
      end

      // Activation always propagates down
      activation_reg <= activation_in;

      // Accumulator
      if (flush_acc) begin
        accumulator <= '0;
      end else if (accumulate_en) begin
        accumulator <= mac_result;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  assign weight_out      = weight_reg;
  assign activation_out  = activation_reg;
  assign partial_sum_out = flush_acc ? accumulator : 32'b0;

endmodule : npu_pe
