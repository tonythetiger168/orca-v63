// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// AIX 介面: CPU AIX uop -> 命令佇列 (doorbell), TDB 檔案 (CSR), 完成回報
module npu_aix_intf
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t aix_uop,
  input  logic aix_valid,
  output logic aix_ready,
  output aix_cmd_t cmd_out,
  output logic     cmd_valid,
  input  logic     cmd_ready,
  input  logic     completion,
  output logic     completion_valid,
  input  logic tdb_we,
  input  logic [7:0] tdb_idx,
  input  aix_tdb_t tdb_wdata,
  output aix_tdb_t tdb_rd [AIX_NUM_TDB]
);
  import orca_pkg::*;
  aix_tdb_t tdb_file [AIX_NUM_TDB];
  assign aix_ready = cmd_ready;
  always_comb begin
    cmd_out.tdb0    = aix_uop.rs2;
    cmd_out.tdb1    = aix_uop.rs1;
    cmd_out.tdb2    = aix_uop.rd;
    cmd_out.opcode  = aix_uop.imm[7:0];
    cmd_out.flags   = aix_uop.imm[15:8];
    cmd_out.tile_id = aix_uop.imm[18:16];
    cmd_out.length  = aix_uop.imm[50:19];
    cmd_valid          = aix_valid;
    completion_valid   = completion;
    for (int i = 0; i < AIX_NUM_TDB; i++) tdb_rd[i] = tdb_file[i];
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < AIX_NUM_TDB; i++) tdb_file[i] <= '0;
    end else if (tdb_we) begin
      tdb_file[tdb_idx] <= tdb_wdata;
    end
  end
endmodule : npu_aix_intf
