// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// Cluster: 4×CU, 空閒 CU round-robin, 完成聚合
module npu_cluster
  import orca_pkg::*;
#(
  parameter int CLUSTER_ID = 0
)(
  input  logic clk, rst_n,
  input  aix_cmd_t cmd,
  input  logic     cmd_valid,
  output logic     cmd_ready,
  output logic     done,
  output logic     busy
);
  import orca_pkg::*;
  logic cu_rdy [CUS_PER_CLUSTER], cu_done [CUS_PER_CLUSTER];
  logic [7:0] act_zero [PE_ARRAY_DIM];
  logic [7:0] wgt_zero [PE_ARRAY_DIM];
  always_comb for (int j = 0; j < PE_ARRAY_DIM; j++) begin
    act_zero[j] = '0; wgt_zero[j] = '0;
  end
  logic cu_v   [CUS_PER_CLUSTER];
  int free_cu;
  always_comb begin
    free_cu = -1;
    for (int i = 0; i < CUS_PER_CLUSTER; i++)
      if (cu_rdy[i] && free_cu < 0) free_cu = i;
    cmd_ready = (free_cu >= 0);
    for (int i = 0; i < CUS_PER_CLUSTER; i++)
      cu_v[i] = cmd_valid && (i == free_cu);
    done = 1'b0;
    for (int i = 0; i < CUS_PER_CLUSTER; i++) done = done | cu_done[i];
    busy = !cmd_ready;
  end
  genvar i;
  generate
    for (i = 0; i < CUS_PER_CLUSTER; i++) begin : g_cu
      npu_cu u_cu (
        .clk(clk), .rst_n(rst_n),
        .cmd(cmd), .cmd_valid(cu_v[i]), .cmd_ready(cu_rdy[i]), .done(cu_done[i]),
        .act_in(act_zero), .wgt_in(wgt_zero), .result());
    end
  endgenerate
endmodule : npu_cluster
