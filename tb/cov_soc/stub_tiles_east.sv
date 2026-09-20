// SPDX-License-Identifier: Apache-2.0
// stub_tiles_east.sv (v6.3.4 fix BUG-C): soc_east_tb 專用 directed 空殼 tile
// 與 stub_tiles.sv 同 port。cpu tile 0 內建 directed 注入序列 (initial/task,
// --timing 下合法): 依序發出 soc_east_tb 各測項之 flit, 每筆恰佔一拍
// (soc_east_tb 令 clk_sys==clk_noc, 保證恰一筆 buffer write, 無重複無遺漏)。
// 其餘 tile 不發流 (noc_out 恆 FLIT_EMPTY), 被動接收供 TB 監察。
`include "orca_pkg.sv"

module orca_v63_cpu_tile
  import orca_pkg::*;
#(
  parameter int TILE_ID = 0,
  parameter int NCO = CORES_PER_CPU_TILE
)(
  input  logic clk, rst_n,
  output flit_t noc_out,
  input  flit_t noc_in,
  output logic  noc_out_ready,
  input  logic  noc_in_valid,
  input  logic [7:0] irq_lines,
  output logic irq_ack,
  input  logic  noc_out_ready_i
);
  flit_t noc_out_r;
  assign noc_out       = noc_out_r;
  assign noc_out_ready = 1'b1;
  assign irq_ack       = ^irq_lines;

  function automatic flit_t mkf(input logic [1:0] dx, dy, vc,
                                input flit_type_t ft, input logic [511:0] pl);
    flit_t f;
    f = '0;
    f.valid = 1'b1; f.ftype = ft;
    f.dest_x = dx; f.dest_y = dy;
    f.src_x  = NOC_X_BITS'(TILE_ID); f.src_y = '0;
    f.vc_id  = vc; f.payload = pl;
    return f;
  endfunction

  task automatic emit(input flit_t f);
    noc_out_r = f;
    @(negedge clk);
    noc_out_r = `FLIT_EMPTY;
    repeat (3) @(negedge clk);
  endtask

  // v6.3.4 fix BUG-C: directed 序列 — 對應 soc_east_tb 測項 (i)~(v)
  initial begin
    noc_out_r = `FLIT_EMPTY;
    if (TILE_ID == 0) begin
      @(posedge rst_n);
      repeat (6) @(negedge clk);
      // (i) 單跳 EAST: (0,0)->(1,0) vc0
      emit(mkf(2'd1, 2'd0, 2'd0, FLIT_SINGLE, 512'hE457_0001_D15EA5E0));
      // (ii) 多跳 EAST: (0,0)->(3,0) vc1
      emit(mkf(2'd3, 2'd0, 2'd1, FLIT_SINGLE, 512'hE457_3009_F00D));
      // (iii) XY 轉彎: (0,0)->(1,1) vc2 (先 E 後 N)
      emit(mkf(2'd1, 2'd1, 2'd2, FLIT_SINGLE, 512'h7021_E211_ABCD));
      // (iv) VC 掃描 0..3: (0,0)->(1,0)
      for (int v = 0; v < 4; v++)
        emit(mkf(2'd1, 2'd0, 2'(v), FLIT_SINGLE, {448'h0, 64'hC0DE_4C00} + 512'(v)));
      // (v) 多 flit packet: HEAD+TAIL -> (1,1) (同 VC 保序, TAIL 滿 512b payload)
      emit(mkf(2'd1, 2'd1, 2'd0, FLIT_HEAD, {64'hA55A_0000_1111_0000, 448'h0}));
      noc_out_r = mkf(2'd1, 2'd1, 2'd0, FLIT_TAIL, {16{32'hCAFE_F00D}});
      @(negedge clk);
      noc_out_r = `FLIT_EMPTY;
    end
  end
  wire unused = &{1'b0, noc_in, noc_in_valid, noc_out_ready_i};
endmodule : orca_v63_cpu_tile

module orca_v63_ai_tile
  import orca_pkg::*;
#(
  parameter int TILE_ID = 0,
  parameter int NCLUSTERS = CLUSTERS_PER_TILE
)(
  input  logic clk, rst_n,
  input  uop_t  aix_uop,
  input  logic  aix_valid,
  output logic  aix_ready,
  output flit_t noc_out,
  input  logic  noc_out_ready,
  input  flit_t noc_in,
  input  logic  noc_in_valid,
  output logic  noc_in_ready,
  output logic  aix_irq,
  output logic [HBM3_STACKS-1:0] hbm_ck_t, hbm_ck_c, hbm_cs_n,
  output logic  hbm_init_done
);
  assign noc_out       = `FLIT_EMPTY;
  assign aix_ready     = 1'b1;
  assign noc_in_ready  = 1'b1;
  assign aix_irq       = 1'b0;
  assign hbm_ck_t      = '0;
  assign hbm_ck_c      = '1;
  assign hbm_cs_n      = '1;
  assign hbm_init_done = 1'b1;
  wire unused = &{1'b0, clk, rst_n, aix_uop, aix_valid, noc_out_ready,
                  noc_in, noc_in_valid, TILE_ID[0]};
endmodule : orca_v63_ai_tile
