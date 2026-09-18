// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 計算單元: systolic array + accumulator 控制, LOAD->COMP->DRAIN
module npu_cu
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  aix_cmd_t cmd,
  input  logic     cmd_valid,
  output logic     cmd_ready,
  output logic     done,
  input  logic [7:0]  act_in  [PE_ARRAY_DIM],
  input  logic [7:0]  wgt_in  [PE_ARRAY_DIM],
  output logic [31:0] result  [PE_ARRAY_DIM]
);
  import orca_pkg::*;
  typedef enum logic [1:0] {CU_IDLE, CU_COMP, CU_DRAIN} cst_t;
  cst_t st;
  logic [15:0] iter;
  logic acc_en, acc_flush;
  assign cmd_ready = (st == CU_IDLE);
  assign done      = (st == CU_DRAIN) && (iter == 0);

  logic psum_v [PE_ARRAY_DIM];
  logic        psum_r;
  npu_systolic u_array (
    .clk(clk), .rst_n(rst_n),
    .weight_load_data(wgt_in), .weight_load_valid(cmd_valid), .weight_load_row('0),
    .weight_load_ready(),
    .activation_in(act_in), .activation_valid(acc_en), .activation_ready(),
    .partial_sum_out(result), .partial_sum_valid(psum_v), .partial_sum_ready(psum_r),   // scalar
    .dtype(cmd.flags[2:0]), .weight_stationary(1'b1),
    .accumulate_en(acc_en), .flush_acc(acc_flush),
    .sparse_mode(1'b0), .sparse_mask('0));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= CU_IDLE; iter <= '0; acc_en <= 1'b0; acc_flush <= 1'b0; end
    else begin
      acc_flush <= 1'b0;
      unique case (st)
        CU_IDLE: if (cmd_valid) begin st <= CU_COMP; iter <= 16'(cmd.length); end
        CU_COMP: begin
          acc_en <= 1'b1;
          if (iter > 0) iter <= iter - 1'b1;
          else begin st <= CU_DRAIN; acc_flush <= 1'b1; end
        end
        CU_DRAIN: begin acc_en <= 1'b0; st <= CU_IDLE; end
        default: st <= CU_IDLE;
      endcase
    end
  end
endmodule : npu_cu
