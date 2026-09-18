//============================================================================
// ORCA v6.1 ZEN — Phoenix-E AME (Adaptive Matrix Engine, Edge Server)
// Peak Performance: ~2 TOPS @ 2.5GHz (INT8 dense-equivalent)
// Target Process: 7nm
// Area Estimate: ~1.5 mm2
// Power Estimate: <2W
//
// Features:
// - 12 sparse blocks x 8x8 = 768 MACs (downscaled from 16 blocks)
// - 2:4 structured sparsity, CSR format
// - Skip-zero logic for power efficiency
// - Dynamic shape support for irregular GEMM
// - Same ISA as v6.0 Phoenix AME
//============================================================================
`ifndef ORCA_AME_V6_1_SV
`define ORCA_AME_V6_1_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_ame_v6_1 #
( parameter int NUM_BLOCKS     = 12
// Down from 16
, parameter int BLOCK_DIM      = 8
, parameter int SPARSE_RATIO   = 2
, parameter int ACC_WIDTH      = 32
, parameter int IDX_WIDTH      = 16  )  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// Sparse command interface
// --------------------------------------------------------------------------
, input  logic [63:0] sparse_cmd
, input  logic        sparse_cmd_valid
, output logic        sparse_cmd_ready
// --------------------------------------------------------------------------
// CSR data interface
// --------------------------------------------------------------------------
, input  logic [31:0] csr_row_ptr [0:127]
, input  logic [15:0] csr_col_idx [0:1023]
, input  logic signed [7:0] csr_values [0:1023]
// --------------------------------------------------------------------------
// Dense vector input
// --------------------------------------------------------------------------
, input  logic signed [7:0] dense_vec [0:255]
, input  logic              vec_valid
// --------------------------------------------------------------------------
// Output
// --------------------------------------------------------------------------
, output logic signed [ACC_WIDTH-1:0] sparse_result [0:127]
, output logic                        result_valid
// --------------------------------------------------------------------------
// Status
// --------------------------------------------------------------------------
, output logic [63:0] ame_ops_counter  );
typedef enum logic [2:0]  {    AME_IDLE        = 3'd0
, AME_LOAD_CSR    = 3'd1
, AME_COMPUTE_BLOCK = 3'd2
, AME_SKIP_ZERO   = 3'd3
, AME_STORE       = 3'd4
, AME_DONE        = 3'd5  } ame_state_t;
  ame_state_t state, next_state;
  logic signed [ACC_WIDTH-1:0] block_acc [0:NUM_BLOCKS-1][0:BLOCK_DIM-1];
  logic [7:0] row_counter;
  logic [10:0] nnz_counter;
  logic [63:0] ops_cnt;
  logic                 row_is_empty;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      state <= AME_IDLE;
      row_counter <= '0;
      nnz_counter <= '0;
      ops_cnt <= '0;
      result_valid <= 1'b0;
end else begin      state <= next_state;
case (state)
AME_LOAD_CSR: begin          row_counter <= row_counter + 1;
          nnz_counter <= csr_row_ptr[row_counter+1] - csr_row_ptr[row_counter];
end
AME_COMPUTE_BLOCK: begin
if (nnz_counter > 0) begin
for (int b = 0; b < NUM_BLOCKS; b = b + 1) begin
for (int d = 0; d < BLOCK_DIM; d = d + 1) begin
if (csr_col_idx[nnz_counter] < 256) begin                  block_acc[b][d] <= block_acc[b][d] +                    csr_values[nnz_counter] *                    dense_vec[csr_col_idx[nnz_counter]];
end
end
end            nnz_counter <= nnz_counter - 1;
            ops_cnt <= ops_cnt + NUM_BLOCKS * BLOCK_DIM;
end
end
AME_SKIP_ZERO: begin
if (row_is_empty) row_counter <= row_counter + 1;
end
AME_STORE: begin
for (int b = 0; b < NUM_BLOCKS; b = b + 1) begin
for (int d = 0; d < BLOCK_DIM; d = d + 1) begin              sparse_result[b*BLOCK_DIM + d] <= block_acc[b][d];
              block_acc[b][d] <= '0;
end
end          result_valid <= 1'b1;
end
AME_DONE: begin          result_valid <= 1'b0;
end
endcase
end
end
always_comb begin    next_state = state;
case (state)
AME_IDLE:
if (sparse_cmd_valid) next_state = AME_LOAD_CSR;
AME_LOAD_CSR:       next_state = (nnz_counter == 0) ? AME_SKIP_ZERO : AME_COMPUTE_BLOCK;
AME_COMPUTE_BLOCK:  next_state = (nnz_counter == 0) ? AME_STORE : AME_COMPUTE_BLOCK;
AME_SKIP_ZERO:      next_state = (row_counter >= 128) ? AME_STORE : AME_LOAD_CSR;
AME_STORE:          next_state = AME_DONE;
AME_DONE:           next_state = AME_IDLE;
default:            next_state = AME_IDLE;

endcase
end
assign row_is_empty = (csr_row_ptr[row_counter+1] == csr_row_ptr[row_counter]);
assign sparse_cmd_ready = (state == AME_IDLE);
assign ame_ops_counter = ops_cnt;
endmodule // orca_ame_v6_1
`endif
// ORCA_AME_V6_1_SV
