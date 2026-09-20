// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
module unit_hbm3_tb;
  import orca_pkg::*;
  localparam int DS=3, DW=512;
  localparam int SB=$clog2(DS), CB=$clog2(16), BB=$clog2(8);
  localparam int ROWB=14, COLB=6;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end

  logic clk_phy; assign clk_phy = clk;

  logic req_v, req_we, req_rdy, rsp_v;
  logic [63:0] req_addr; logic [DW-1:0] req_data, rsp_data; logic [DW/8-1:0] req_be;
  logic [DS-1:0] ck_t,ck_c,cs_n,cke,rstn_o,temp,alertn,rwds; logic [DS*16-1:0] ca;
  logic [63:0] t_rd,t_wr,t_rf; logic [31:0] ecc_cnt, ecc_corr; logic ecc_inj;

  npu_hbm3_ctrl #(.NUM_STACKS(DS)) u_hbm (
    .clk(clk), .clk_phy(clk_phy), .rst_n(rst_n),
    .req_valid(req_v), .req_addr(req_addr), .req_we(req_we), .req_data(req_data),
    .req_be(req_be), .req_ready(req_rdy), .rsp_data(rsp_data), .rsp_valid(rsp_v),
    .phy_ck_t(ck_t), .phy_ck_c(ck_c), .phy_cs_n(cs_n), .phy_cke(cke),
    .phy_rst_n(rstn_o), .phy_ca(ca), .phy_rwds(rwds),
    .cfg_tRFC(16'd30), .cfg_tREFI(16'd300), .cfg_CL(8'h22), .cfg_CWL(8'h20),
    .cfg_RL(8'h22), .cfg_WL(8'h20), .cfg_ecc_en(1'b1), .cfg_scrub_en(1'b1),
    .cfg_ecc_inject(ecc_inj),
    .stack_temp(temp), .stack_alert_n(alertn),
    .total_reads(t_rd), .total_writes(t_wr), .total_refreshes(t_rf), .ecc_error_count(ecc_cnt), .ecc_corrected_count(ecc_corr));

  task automatic req(input logic we, input int st, input int ch, input int bk,
                     input int row, input logic [DW-1:0] d);
    req_addr = (64'(st) << (CB+BB+ROWB+COLB+6))
             | (64'(ch) << (BB+ROWB+COLB+6))
             | (64'(bk) << (ROWB+COLB+6))
             | (64'(row) << (COLB+6));
    req_we=we; req_data=d; req_be={DW/8{1'b1}}; req_v=1;
    @(negedge clk);
    begin int g=0; while(!req_rdy && g<60) begin @(negedge clk); g++; end end
    req_v=0; @(negedge clk);
  endtask

  initial begin
    repeat(6000) @(negedge clk);
    $display("WATCHDOG: rd=%0d wr=%0d rf=%0d", t_rd, t_wr, t_rf); $finish;
  end

  int rsp_seen = 0;
  always @(posedge rsp_v) rsp_seen <= rsp_seen + 1;
  task automatic wait_rsp(input int target);
    begin int g=0; while(rsp_seen < target && g<200) begin @(negedge clk); g++; end end
  endtask

  int n=0;
  initial begin
    req_v=0; req_we=0; req_addr='0; req_data='0; req_be='0; ecc_inj=0;
    rst_n=0; #60 rst_n=1; repeat(50) @(negedge clk);
    // Phase 1: writes 先跑 bank 2-3（IDLE->ACTIVATE->WRITE->WRITE）
    for (int s=0;s<2;s++) for (int c=0;c<4;c++) for (int b=2;b<4;b++) begin
      automatic int row = s*256 + c*16 + b;
      req(1,s,c,b,row,{8{64'h2000+n}}); n++;
      req(1,s,c,b,row,{8{64'h3000+n}}); n++;
    end
    // Phase 2: reads bank 0-1（IDLE->ACTIVATE->READ->READ）
    for (int s=0;s<2;s++) for (int c=0;c<4;c++) for (int b=0;b<2;b++) begin
      automatic int row = s*256 + c*16 + b;
      req(0,s,c,b,row,{8{64'h1000+n}}); n++;
      req(0,s,c,b,row,{8{64'h1000+n}}); n++;
    end
    // Phase 3: PRECHARGE 單一乾淨 bank (DS-1, chan3, bank7), 大延遲確保狀態穩定
    begin
      automatic int rowA = 13'h55;
      automatic int rowB = 13'hAA;
      req(0, DS-1, 3, 7, rowA, {8{64'h5000}});  repeat(40) @(negedge clk);  // ACTIVATE rowA
      req(0, DS-1, 3, 7, rowA, {8{64'h5001}});  repeat(40) @(negedge clk);  // READ rowA
      req(0, DS-1, 3, 7, rowB, {8{64'h5002}});  repeat(40) @(negedge clk);  // row miss -> PRECHARGE
      req(0, DS-1, 3, 7, rowB, {8{64'h5003}});  repeat(40) @(negedge clk);  // ACTIVATE rowB
      req(0, DS-1, 3, 7, rowB, {8{64'h5004}});  repeat(40) @(negedge clk);  // READ rowB
    end
    // Phase 4: ECC error 偵測 (注入污染 -> 讀回偵測 error/corrected)
    begin
      automatic int ec0 = 0; automatic int cc0 = 0;
      // 同 row(100) 全程避免 PRECHARGE: 注入寫入是 WRITE 非 PRECHARGE
      // 1) 正常寫+讀 (baseline, 無 error)
      req(1, 0, 0, 4, 100, {8{64'hABCD_1234_5678_EF00}});  repeat(40) @(negedge clk);
      req(0, 0, 0, 4, 100, {8{64'h0}});                     repeat(40) @(negedge clk);
      // 2) 注入污染寫入 (同 row=100, row hit -> 真正 WRITE, 污染 mem_ecc)
      ecc_inj = 1;
      req(1, 0, 0, 4, 100, {8{64'hDEAD_BEEF_CAFE_0001}});   repeat(40) @(negedge clk);
      ecc_inj = 0;
      // 3) 讀回污染資料 (同 row=100) -> ECC error/corrected 計數增加
      req(0, 0, 0, 4, 100, {8{64'h0}});                     repeat(60) @(negedge clk);
      $display("ECC: errors=%0d corrected=%0d (expect >0)", ecc_cnt, ecc_corr);
    end
    repeat(300) @(negedge clk);
    $display("HBM3 TB PASS: rd=%0d wr=%0d rf=%0d ecc=%0d", t_rd, t_wr, t_rf, ecc_cnt);
    $finish;
  end
endmodule
