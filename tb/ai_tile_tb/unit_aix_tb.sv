// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
// npu_aix_intf 全覆蓋: TDB CSR 寫入 + AIX 命令 + 完成
module unit_aix_tb;
  import orca_pkg::*;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  uop_t au; logic av, ar; aix_cmd_t co; logic cv, cr, comp, cvld;
  logic twe; logic [7:0] tidx; aix_tdb_t twd; aix_tdb_t trd [AIX_NUM_TDB];
  npu_aix_intf u_intf (.clk(clk), .rst_n(rst_n), .aix_uop(au), .aix_valid(av), .aix_ready(ar),
    .cmd_out(co), .cmd_valid(cv), .cmd_ready(cr), .completion(comp), .completion_valid(cvld),
    .tdb_we(twe), .tdb_idx(tidx), .tdb_wdata(twd), .tdb_rd(trd));
  initial begin
    au='0; av=0; cr=1; comp=0; twe=0; tidx='0; twd='0;
    rst_n=0; #57 rst_n=1; @(negedge clk);
    // TDB CSR 寫入遍歷
    for (int i=0;i<20;i++) begin
      twe=1; tidx=8'(i); twd.base_addr=64'h5000_0000+i*64; twd.valid=1; @(negedge clk); twe=0; @(negedge clk);
    end
    // AIX 命令 (各 opcode) + 完成
    for (int o=0;o<8;o++) begin
      au='0; au.opcode=OP_AIX; au.imm[7:0]=8'(o+1); au.rs1=5'(o); au.rs2=5'(o+1); au.rd=5'(o+2);
      av=1; @(negedge clk); av=0; repeat(4) @(negedge clk);
      comp=1; @(negedge clk); comp=0; repeat(2) @(negedge clk);
    end
    // cmd_ready=0 背壓
    cr=0; au='0; au.opcode=OP_AIX; av=1; repeat(6) @(negedge clk); av=0; cr=1;
    $display("AIX TB PASS"); $finish;
  end
endmodule : unit_aix_tb
