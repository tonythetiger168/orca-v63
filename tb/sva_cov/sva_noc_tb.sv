// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.3.2 SVA 覆蓋率 TB - NoC (改造自 tb/cov_f5/orca_noc_router_cov_tb.sv
// 與 orca_noc_link_retry_tb.sv 元素; 原檔未動)
// DUT: orca_noc_router (X=1,Y=1,BUF_DEPTH=4,DW=$bits(flit_t)=525)
//      + orca_chi_coh x2 (coh_* 觀察點, router 無一致性狀態 [N4])
// Checker: sva_noc_cov (12 顆 property 量測)
`include "orca_pkg.sv"

module sva_noc_tb;
  import orca_pkg::*;
  import orca_chi_pkg::*;
  localparam int DW = $bits(flit_t);   // v6.3.4 fix BUG-C: 516 -> 525 (pkg flit_t)
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [DW-1:0] n_rx_d, s_rx_d, e_rx_d, w_rx_d, l_rx_d;
  logic          n_rx_v, s_rx_v, e_rx_v, w_rx_v, l_rx_v;
  logic          n_rx_r, s_rx_r, e_rx_r, w_rx_r, l_rx_r;
  logic [DW-1:0] n_tx_d, s_tx_d, e_tx_d, w_tx_d, l_tx_d;
  logic          n_tx_v, s_tx_v, e_tx_v, w_tx_v, l_tx_v;
  logic          n_tx_r, s_tx_r, e_tx_r, w_tx_r, l_tx_r;

  orca_noc_router #(.X_POS(1), .Y_POS(1), .BUF_DEPTH(4), .DATA_WIDTH(DW)) u_rtr (
    .clk(clk), .rst_n(rst_n),
    .north_rx_data(n_rx_d), .north_rx_valid(n_rx_v), .north_rx_ready(n_rx_r),
    .north_tx_data(n_tx_d), .north_tx_valid(n_tx_v), .north_tx_ready(n_tx_r),
    .south_rx_data(s_rx_d), .south_rx_valid(s_rx_v), .south_rx_ready(s_rx_r),
    .south_tx_data(s_tx_d), .south_tx_valid(s_tx_v), .south_tx_ready(s_tx_r),
    .east_rx_data (e_rx_d), .east_rx_valid (e_rx_v), .east_rx_ready (e_rx_r),
    .east_tx_data (e_tx_d), .east_tx_valid (e_tx_v), .east_tx_ready (e_tx_r),
    .west_rx_data (w_rx_d), .west_rx_valid (w_rx_v), .west_rx_ready (w_rx_r),
    .west_tx_data (w_tx_d), .west_tx_valid (w_tx_v), .west_tx_ready (w_tx_r),
    .local_rx_data(l_rx_d), .local_rx_valid(l_rx_v), .local_rx_ready(l_rx_r),
    .local_tx_data(l_tx_d), .local_tx_valid(l_tx_v), .local_tx_ready(l_tx_r));

  // ---------------- chi 一致性代理 x2 ([N4]: coh 觀察點) ----------------
  paddr_t c0_addr;  logic c0_v;  chi_req_op_t c0_op;  logic c0_snp;
  paddr_t c1_addr;  logic c1_v;  chi_req_op_t c1_op;  logic c1_snp;
  coh_state_t c0_state, c1_state;  logic c0_sack, c1_sack;

  orca_chi_coh u_coh0 (
    .clk(clk), .rst_n(rst_n),
    .req_addr(c0_addr), .req_valid(c0_v), .req_op(c0_op), .req_ready(),
    .rsp_data(), .rsp_valid(),
    .snp_addr('0), .snp_valid(c0_snp), .snp_state(c0_state),
    .snp_dirty(), .snp_data(), .snp_ack(c0_sack));
  orca_chi_coh u_coh1 (
    .clk(clk), .rst_n(rst_n),
    .req_addr(c1_addr), .req_valid(c1_v), .req_op(c1_op), .req_ready(),
    .rsp_data(), .rsp_valid(),
    .snp_addr('0), .snp_valid(c1_snp), .snp_state(c1_state),
    .snp_dirty(), .snp_data(), .snp_ack(c1_sack));

  // ---------------- SVA checker 銜接 ----------------
  logic [4:0] w_rx_valid, w_rx_ready, w_tx_valid, w_tx_ready;
  logic [511:0] w_rx_data [5];
  logic [511:0] w_tx_data [5];
  logic [4:0] [3:0] w_dest_x, w_dest_y, w_vc;
  coh_state_t [4:0] w_coh_rx, w_coh_tx;
  logic [4:0] w_coh_req, w_coh_rsp;

  // v6.3.4 fix BUG-C: pkg flit_t 標頭欄位 (dest_x[12:11] dest_y[10:9] vc_id[4:3])
  function automatic logic [3:0] f_dx(input logic [DW-1:0] f); flit_t t; t = flit_t'(f); return {2'b0, t.dest_x}; endfunction
  function automatic logic [3:0] f_dy(input logic [DW-1:0] f); flit_t t; t = flit_t'(f); return {2'b0, t.dest_y}; endfunction
  function automatic logic [3:0] f_vc(input logic [DW-1:0] f); flit_t t; t = flit_t'(f); return {2'b0, t.vc_id}; endfunction
  function automatic logic [511:0] f_pl(input logic [DW-1:0] f); flit_t t; t = flit_t'(f); return t.payload; endfunction

  always_comb begin
    w_rx_valid = {l_rx_v, w_rx_v, e_rx_v, s_rx_v, n_rx_v};
    w_rx_ready = {l_rx_r, w_rx_r, e_rx_r, s_rx_r, n_rx_r};
    w_tx_valid = {l_tx_v, w_tx_v, e_tx_v, s_tx_v, n_tx_v};
    w_tx_ready = {l_tx_r, w_tx_r, e_tx_r, s_tx_r, n_tx_r};
    // v6.3.4 fix BUG-C: 512b 觀察窗取 pkg payload (原切低 512b 已不含 payload 高位)
    w_rx_data = '{f_pl(n_rx_d), f_pl(s_rx_d), f_pl(e_rx_d), f_pl(w_rx_d), f_pl(l_rx_d)};
    w_tx_data = '{f_pl(n_tx_d), f_pl(s_tx_d), f_pl(e_tx_d), f_pl(w_tx_d), f_pl(l_tx_d)};
    // dest/vc: tx 側為主; local 埠在 rx_valid 時取 rx 側 (N6), 否則 tx 側 (N5)
    w_dest_x[0] = f_dx(n_tx_d); w_dest_y[0] = f_dy(n_tx_d); w_vc[0] = f_vc(n_rx_d);
    w_dest_x[1] = f_dx(s_tx_d); w_dest_y[1] = f_dy(s_tx_d); w_vc[1] = f_vc(s_rx_d);
    w_dest_x[2] = f_dx(e_tx_d); w_dest_y[2] = f_dy(e_tx_d); w_vc[2] = f_vc(e_rx_d);
    w_dest_x[3] = f_dx(w_tx_d); w_dest_y[3] = f_dy(w_tx_d); w_vc[3] = f_vc(w_rx_d);
    w_dest_x[4] = l_rx_v ? f_dx(l_rx_d) : f_dx(l_tx_d);
    w_dest_y[4] = l_rx_v ? f_dy(l_rx_d) : f_dy(l_tx_d);
    w_vc[4]     = f_vc(l_rx_d);
    // coh: LOCAL 埠接兩個 chi agent, 其餘埠 INVALID
    for (int p = 0; p < 5; p++) begin
      w_coh_rx[p]  = (p == 4) ? c0_state : COH_INVALID;
      w_coh_tx[p]  = (p == 4) ? c1_state : COH_INVALID;
      w_coh_req[p] = (p == 4) ? c0_v     : 1'b0;
      w_coh_rsp[p] = (p == 4) ? c0_sack  : 1'b0;
    end
  end

  sva_noc_cov #(.X_POS(1), .Y_POS(1)) u_cov (
    .clk(clk), .rst_n(rst_n),
    .rx_valid(w_rx_valid), .rx_ready(w_rx_ready),
    .tx_valid(w_tx_valid), .tx_ready(w_tx_ready),
    .rx_data(w_rx_data), .tx_data(w_tx_data),
    .dest_x(w_dest_x), .dest_y(w_dest_y), .vc_id(w_vc),
    .coh_state_rx(w_coh_rx), .coh_state_tx(w_coh_tx),
    .coh_req_valid(w_coh_req), .coh_rsp_valid(w_coh_rsp));

  // Build a pkg-format flit (v6.3.4 fix BUG-C, 同 orca_noc_router_cov_tb)
  function automatic logic [DW-1:0] mkflit(input logic [3:0] dx, dy,
                                           input logic [3:0] vc,
                                           input logic [511:0] pl);
    flit_t f;
    f         = '0;
    f.valid   = 1'b1;
    f.ftype   = FLIT_SINGLE;
    f.dest_x  = NOC_X_BITS'(dx);
    f.dest_y  = NOC_Y_BITS'(dy);
    f.src_x   = 2'h2;
    f.src_y   = 2'h1;
    f.vc_id   = vc[1:0];
    f.payload = pl;
    return f;
  endfunction

  int errors = 0;

  task automatic do_route(input logic [3:0] dx, dy, input int exp);
    logic [DW-1:0] f;
    logic [DW-1:0] got;
    logic          v;
    f = mkflit(dx, dy, {2'b0, exp[1:0]}, {468'h0, exp[3:0]});
    @(negedge clk);
    l_rx_d = f; l_rx_v = 1'b1;
    @(negedge clk);
    l_rx_v = 1'b0;
    case (exp)
      0: begin v = n_tx_v; got = n_tx_d; end
      1: begin v = s_tx_v; got = s_tx_d; end
      2: begin v = e_tx_v; got = e_tx_d; end
      3: begin v = w_tx_v; got = w_tx_d; end
      default: begin v = l_tx_v; got = l_tx_d; end
    endcase
    if (v !== 1'b1) begin
      errors++;
      $display("TB FAIL: no tx_valid on port %0d for dest (%0d,%0d)", exp, dx, dy);
    end else if (got !== f) begin
      errors++;
      $display("TB FAIL: data mismatch on port %0d", exp);
    end
    if (({l_tx_v, w_tx_v, e_tx_v, s_tx_v, n_tx_v} & ~(5'b1 << exp)) !== 5'b0) begin
      errors++;
      $display("TB FAIL: multiple tx_valid for dest (%0d,%0d)", dx, dy);
    end
    @(negedge clk);
  endtask

  initial begin
    n_rx_d='0; s_rx_d='0; e_rx_d='0; w_rx_d='0; l_rx_d='0;
    n_rx_v=0; s_rx_v=0; e_rx_v=0; w_rx_v=0; l_rx_v=0;
    n_tx_r=1; s_tx_r=1; e_tx_r=1; w_tx_r=1; l_tx_r=1;
    c0_addr='0; c0_v=0; c0_op=CHI_RD; c0_snp=0;
    c1_addr='0; c1_v=0; c1_op=CHI_RD; c1_snp=0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);

    // ---- 路由: 全 5 方向 (含 N5/N6 前提) ----
    do_route(4'd1, 4'd1, 4); // LOCAL
    do_route(4'd3, 4'd1, 2); // EAST
    do_route(4'd0, 4'd1, 3); // WEST
    do_route(4'd1, 4'd3, 0); // NORTH
    do_route(4'd1, 4'd0, 1); // SOUTH

    // ---- 各輸入埠注入 (vc 0 再 1: N4 cover) ----
    @(negedge clk); n_rx_d = mkflit(4'd1,4'd1,4'd0,472'h1); n_rx_v = 1;
    @(negedge clk); n_rx_d = mkflit(4'd1,4'd1,4'd1,472'h9); // vc0->vc1 (N4)
    @(negedge clk); n_rx_v = 0;
    @(negedge clk); s_rx_d = mkflit(4'd1,4'd1,4'd1,472'h2); s_rx_v = 1;
    @(negedge clk); s_rx_v = 0;
    @(negedge clk); e_rx_d = mkflit(4'd1,4'd1,4'd2,472'h3); e_rx_v = 1;
    @(negedge clk); e_rx_v = 0;
    @(negedge clk); w_rx_d = mkflit(4'd1,4'd1,4'd3,472'h4); w_rx_v = 1;
    @(negedge clk); w_rx_v = 0;
    repeat (4) @(negedge clk);

    // ---- 背壓: east 3 拍 (<10: N1b/N3 成立) ----
    e_tx_r = 1'b0;
    @(negedge clk);
    l_rx_d = mkflit(4'd3, 4'd1, 4'd0, 472'hBEEF); l_rx_v = 1'b1;
    @(negedge clk);
    l_rx_v = 1'b0;
    repeat (3) @(negedge clk);
    if (e_tx_v !== 1'b0) begin
      errors++; $display("TB FAIL: east_tx_valid while ready=0");
    end
    e_tx_r = 1'b1;
    @(posedge clk);
    if (e_tx_v !== 1'b1 || e_tx_d !== mkflit(4'd3,4'd1,4'd0,472'hBEEF)) begin
      errors++; $display("TB FAIL: backpressured east flit not drained");
    end
    repeat (2) @(negedge clk);

    // ---- north VC1 3 flits 背壓後 drain (同原 TB) ----
    n_tx_r = 1'b0;
    for (int i = 0; i < 3; i++) begin
      @(negedge clk);
      l_rx_d = mkflit(4'd1, 4'd3, 4'd1, 472'(100+i)); l_rx_v = 1'b1;
    end
    @(negedge clk); l_rx_v = 1'b0;
    repeat (2) @(negedge clk);
    n_tx_r = 1'b1;
    begin
      int drained;
      drained = 0;
      for (int i = 0; i < 12 && drained < 3; i++) begin
        @(posedge clk);
        if (n_tx_v) drained++;
      end
      if (drained != 3) begin
        errors++; $display("TB FAIL: expected 3 north flits drained, got %0d", drained);
      end
    end
    repeat (2) @(negedge clk);

    // ---- 一致性序列 (N7/N8/N9) ----
    // c1: CHI_RDO -> E (非 S)
    @(negedge clk); c1_v = 1; c1_op = CHI_RDO; c1_addr = 64'h1000;
    @(negedge clk); c1_v = 0;
    // c0: CHI_WR -> M (N7 前提: c0==M 且 c1!=S)
    @(negedge clk); c0_v = 1; c0_op = CHI_WR; c0_addr = 64'h2000;
    @(negedge clk); c0_v = 0;
    repeat (2) @(negedge clk);
    if (c0_state != COH_MODIFIED) begin errors++; $display("TB FAIL: coh0 not M"); end
    if (c1_state != COH_EXCLUSIVE) begin errors++; $display("TB FAIL: coh1 not E"); end
    // N8: snp (rsp) 與 req 不同拍
    @(negedge clk); c0_snp = 1;
    @(negedge clk); c0_snp = 0;
    // N9: c0==M 且 local 背壓 1 拍, 不發 req -> 下拍仍 M
    @(negedge clk); l_tx_r = 1'b0;
    @(negedge clk); l_tx_r = 1'b1;
    if (c0_state != COH_MODIFIED) begin errors++; $display("TB FAIL: M lost under backpressure"); end
    // 收尾: evict 兩節點
    @(negedge clk); c0_v = 1; c0_op = CHI_EVICT;
    @(negedge clk); c0_v = 0; c1_v = 1; c1_op = CHI_EVICT;
    @(negedge clk); c1_v = 0;
    repeat (3) @(negedge clk);

    // ---- SVA checker 結果併入 PASS 判定 ----
    for (int i = 0; i < 12; i++) begin
      if (i == 11) continue;  // N10: N/A (結構性不可觸發, 見報告)
      if (u_cov.att[i] < 1) begin
        errors++; $display("ERR: SVA property %0d (%s) vacuous", i, u_cov.PNAME[i]);
      end
      if (u_cov.fail[i] != 0) begin
        errors++; $display("ERR: SVA property %0d (%s) fails=%0d", i, u_cov.PNAME[i], u_cov.fail[i]);
      end
    end
    if (errors == 0) $display("SVA_NOC_TB PASS");
    else             $display("SVA_NOC_TB FAIL errors=%0d", errors);
    $finish;
  end
endmodule : sva_noc_tb
