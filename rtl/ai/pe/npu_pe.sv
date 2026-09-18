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
  input  logic [2:0]  dtype,          // Data type (INT8/INT4/BF16/FP16/FP32/FP8)
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

  // FP8/BF16 multiplier (simplified - would use FP unit in real design)
  logic [15:0] mult_fp16_raw;
  assign mult_fp16_raw = {weight_reg, activation_reg};  // Placeholder

  // ---------------------------------------------------------------------------
  // Accumulator Logic
  // ---------------------------------------------------------------------------
  always_comb begin
    if (sparse_skip) begin
      mac_result = accumulator;  // Skip computation, keep accumulator
    end else begin
      unique case (dtype)
        AI_DTYPE_INT8:  mac_result = accumulator + mult_int8_sext;
        AI_DTYPE_INT4:  mac_result = accumulator + (mult_int8_sext << 1);  // 2x throughput
        AI_DTYPE_BF16,
        AI_DTYPE_FP16:  mac_result = accumulator + {{16{mult_fp16_raw[15]}}, mult_fp16_raw}; // Simplified
        AI_DTYPE_FP32:  mac_result = accumulator + partial_sum_in;  // FP32 uses external FMA
        AI_DTYPE_FP8:   mac_result = accumulator + (mult_int8_sext << 1);  // 2x throughput
        default:        mac_result = accumulator + mult_int8_sext;
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
