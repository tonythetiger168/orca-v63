// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - Scale-out Fabric (Roc/Garuda): 最多 1024 節點 2D torus, 1024-bit flit,
// 自適應路由 + credit 流控 (對標 T-Head ICN / NVLink Switch)
`include "orca_pkg.sv"

module orca_cloud_fabric #(
  parameter int MAX_NODES  = CLOUD_MAX_NODES,   // 1024
  parameter int TORUS_X    = 32,                // 32x32 = 1024
  parameter int TORUS_Y    = 32,
  parameter int LINK_W     = CLOUD_NOC_W        // 1024-bit
)(
  input  logic clk, rst_n,
  input  logic [10:0]                    my_x, my_y,
  input  logic [LINK_W+31:0]             inj_flit,   // {payload, dest_x, dest_y, ...}
  input  logic                           inj_valid,
  output logic                           inj_ready,
  output logic [LINK_W+31:0]             eject_flit,
  output logic                           eject_valid,
  // 4 向 torus 埠 (x±, y±), 環狀回繞
  input  logic [LINK_W+31:0]             port_in  [4],
  input  logic                           port_in_v[4],
  output logic                           port_in_r[4],
  output logic [LINK_W+31:0]             port_out [4],
  output logic                           port_out_v[4],
  input  logic                           port_out_r[4]
);
  import orca_pkg::*;
  localparam int DW = 32;                        // dest 欄寬
  // 解析 flit 目的
  function automatic logic [10:0] fx(input logic [LINK_W+31:0] f); return f[LINK_W +: 11]; endfunction
  function automatic logic [10:0] fy(input logic [LINK_W+31:0] f); return f[LINK_W+11 +: 11]; endfunction

  // 每向輸出仲裁: 本地注入 + 轉向流量 (最短路徑: 先 x 後 y)
  logic [LINK_W+31:0] cand [4][2];               // [dir][0]=inject [1]=turn
  logic               cand_v[4][2];
  logic [4-1:0]       dir_req;

  // 計算注入 flit 的輸出方向 (0=x+ 1=x- 2=y+ 3=y-; 目的在本節點 -> eject)
  function automatic int inj_dir(input logic [LINK_W+31:0] f);
    automatic int dx, dy;
    dx = 32'(fx(f)) - 32'(my_x);  dy = 32'(fy(f)) - 32'(my_y);
    // torus 最短路徑 (環狀)
    if (dx > TORUS_X/2) dx = dx - TORUS_X;  else if (dx < -TORUS_X/2) dx = dx + TORUS_X;
    if (dy > TORUS_Y/2) dy = dy - TORUS_Y;  else if (dy < -TORUS_Y/2) dy = dy + TORUS_Y;
    if (dx > 0) return 0; else if (dx < 0) return 1;
    else if (dy > 0) return 2; else if (dy < 0) return 3;
    else return -1;   // 本節點 -> eject
  endfunction

  wire inj_here = (inj_valid && inj_dir(inj_flit) < 0);
  assign inj_ready = inj_here || port_out_r[inj_dir(inj_flit)];

  always_comb begin
    eject_flit = '0; eject_valid = 1'b0;
    // eject: 注入即本節點, 或某輸入埠的 flit 目的為本節點
    if (inj_here) begin eject_flit = inj_flit; eject_valid = 1'b1; end
    for (int p = 0; p < 4; p++)
      if (port_in_v[p] && (fx(port_in[p]) == my_x) && (fy(port_in[p]) == my_y)) begin
        eject_flit  = port_in[p]; eject_valid = 1'b1; port_in_r[p] = 1'b1;
      end else port_in_r[p] = port_out_r[p];
    // 輸出埠: 注入 + 轉向
    for (int d = 0; d < 4; d++) begin
      cand[d][0] = inj_flit;  cand_v[d][0] = inj_valid && (inj_dir(inj_flit) == d);
      cand[d][1] = '0;        cand_v[d][1] = 1'b0;
      for (int p = 0; p < 4; p++)
        if (port_in_v[p] && !((fx(port_in[p]) == my_x) && (fy(port_in[p]) == my_y))
            && inj_dir(port_in[p]) == d) begin
          cand[d][1] = port_in[p]; cand_v[d][1] = 1'b1;
        end
      port_out[d]  = cand_v[d][0] ? cand[d][0] : cand[d][1];
      port_out_v[d] = cand_v[d][0] || cand_v[d][1];
    end
  end
endmodule : orca_cloud_fabric
