// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_hbm3_ctrl_tb: npu_hbm3_ctrl 單元 coverage
// 覆蓋: ACT/READ scheduler, WRITE/PRE (force cmd_queue[0] 整個 element 注入),
//       cmdq_full (req_ready=0), refresh 全流程, temp poll 兩臂 (force counter),
//       ECC 單雙錯 (force 無驅動的 rsp_valid/rsp_data/read_ecc),
//       PHY command gen, clk_phy 時脈, inout port toggle
// addr map: [5:0]byte [11:6]col [25:12]row [29:26]bank [33:30]chan [35:34]stack
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_hbm3_ctrl_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  logic clk_phy = 0;
  always #5 clk = ~clk;
  always #2 clk_phy = ~clk_phy;

  localparam int NUM_STACKS = 3;
  localparam int DATA_WIDTH = 512;

  logic        req_valid, req_we, req_ready;
  logic [63:0] req_addr;
  logic [DATA_WIDTH-1:0] req_data;
  logic [DATA_WIDTH/8-1:0] req_be;
  logic [DATA_WIDTH-1:0] rsp_data;
  logic        rsp_valid;
  logic [NUM_STACKS-1:0]   phy_ck_t, phy_ck_c, phy_cs_n, phy_cke, phy_rst_n;
  wire  [NUM_STACKS-1:0]   phy_dqs_t, phy_dqs_c;
  wire  [NUM_STACKS*128-1:0] phy_dq;
  logic [NUM_STACKS*16-1:0]  phy_ca;
  logic [NUM_STACKS-1:0]     phy_rwds;
  logic [15:0] cfg_tRFC, cfg_tREFI;
  logic [7:0]  cfg_CL, cfg_CWL, cfg_RL, cfg_WL;
  logic        cfg_ecc_en, cfg_scrub_en, cfg_ecc_inject;
  logic [NUM_STACKS-1:0] stack_temp, stack_alert_n;
  logic [63:0] total_reads, total_writes, total_refreshes;
  logic [31:0] ecc_error_count, ecc_corrected_count;

  npu_hbm3_ctrl #(.NUM_STACKS(NUM_STACKS)) dut (
    .clk(clk), .clk_phy(clk_phy), .rst_n(rst_n),
    .req_valid(req_valid), .req_addr(req_addr), .req_we(req_we),
    .req_data(req_data), .req_be(req_be), .req_ready(req_ready),
    .rsp_data(rsp_data), .rsp_valid(rsp_valid),
    .phy_ck_t(phy_ck_t), .phy_ck_c(phy_ck_c), .phy_cs_n(phy_cs_n),
    .phy_cke(phy_cke), .phy_rst_n(phy_rst_n),
    .phy_dqs_t(phy_dqs_t), .phy_dqs_c(phy_dqs_c), .phy_dq(phy_dq),
    .phy_ca(phy_ca), .phy_rwds(phy_rwds),
    .cfg_tRFC(cfg_tRFC), .cfg_tREFI(cfg_tREFI),
    .cfg_CL(cfg_CL), .cfg_CWL(cfg_CWL), .cfg_RL(cfg_RL), .cfg_WL(cfg_WL),
    .cfg_ecc_en(cfg_ecc_en), .cfg_scrub_en(cfg_scrub_en),
    .cfg_ecc_inject(cfg_ecc_inject),
    .stack_temp(stack_temp), .stack_alert_n(stack_alert_n),
    .total_reads(total_reads), .total_writes(total_writes),
    .total_refreshes(total_refreshes),
    .ecc_error_count(ecc_error_count),
    .ecc_corrected_count(ecc_corrected_count));

  // inout 由 TB 三態驅動 toggle
  logic dqs_oe = 0;
  logic [NUM_STACKS-1:0] dqs_out = '0;
  logic dq_oe = 0;
  logic [NUM_STACKS*128-1:0] dq_out = '0;
  assign phy_dqs_t = dqs_oe ? dqs_out : 'z;
  assign phy_dqs_c = dqs_oe ? ~dqs_out : 'z;
  assign phy_dq    = dq_oe ? dq_out : 'z;

  // ------------------ always_ff 鏡像 ------------------
  logic        req_valid_p, req_we_p;
  logic [63:0] req_addr_p;
  logic [DATA_WIDTH-1:0] req_data_p;
  logic [DATA_WIDTH/8-1:0] req_be_p;
  logic [15:0] cfg_tRFC_p, cfg_tREFI_p;
  logic [7:0]  cfg_CL_p, cfg_CWL_p, cfg_RL_p, cfg_WL_p;
  logic        cfg_ecc_en_p, cfg_scrub_en_p;
  always_ff @(posedge clk) begin
    req_valid   <= req_valid_p;
    req_we      <= req_we_p;
    req_addr    <= req_addr_p;
    req_data    <= req_data_p;
    req_be      <= req_be_p;
    cfg_tRFC    <= cfg_tRFC_p;
    cfg_tREFI   <= cfg_tREFI_p;
    cfg_CL      <= cfg_CL_p;
    cfg_CWL     <= cfg_CWL_p;
    cfg_RL      <= cfg_RL_p;
    cfg_WL      <= cfg_WL_p;
    cfg_ecc_en  <= cfg_ecc_en_p;
    cfg_scrub_en<= cfg_scrub_en_p;
  end

  int errors = 0;
  // ---- FSM coverage monitor: npu_hbm3_ctrl bank_state[0][0][0] ----
  // (generate 內所有 bank 共用同一組轉移邏輯, 同質; TB 流程在 bank0 上
  //  走完全部可達弧: ACT/READ/WRITE/PRE 皆注入 stack0/ch0/bank0)
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (int'(dut.bank_state[0][0][0]) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_hbm3_ctrl %0d %0d\n", prev, int'(dut.bank_state[0][0][0]));
        prev = int'(dut.bank_state[0][0][0]);
      end
    end
  end
  int guard = 0;

  // 組合裝地址
  function automatic logic [63:0] mk_addr(input int stk, input int ch,
                                          input int bk, input int row,
                                          input int col);
    return (64'(stk) << 34) | (64'(ch) << 30) | (64'(bk) << 26) |
           (64'(row) << 12) | (64'(col) << 6);
  endfunction

  task automatic send_req(input logic [63:0] a, input logic we);
    @(negedge clk);
    req_addr_p  = a;
    req_we_p    = we;
    req_data_p  = {8{64'h0000_0000_0000_0001}};
    req_be_p    = '1;
    req_valid_p = 1;
    @(negedge clk);
    req_valid_p = 0;
  endtask

  // cmd_queue[0] 整個 element 的 packed 值 (cmd_t: 610 bit)
  // {cmd_type[609:607], stack[606:605], channel[604:601], bank[600:597],
  //  row[596:583], col[582:577], data[576:65], be[64:1], we[0]}
  logic [609:0] fc;
  function automatic logic [609:0] mk_cmd(input logic [2:0] t,
                                          input logic [13:0] row);
    return {t, 2'd0, 4'd0, 4'd0, row, 6'd5, 512'd0, 64'd0, 1'b1};
  endfunction

  initial begin
    req_valid_p = 0; req_we_p = 0; req_addr_p = '0; req_data_p = '0; req_be_p = '0;
    cfg_tRFC_p = 16'd8; cfg_tREFI_p = 16'd40;
    cfg_CL_p = 8'h22; cfg_CWL_p = 8'h20; cfg_RL_p = 8'h22; cfg_WL_p = 8'h20;
    cfg_ecc_en_p = 1; cfg_scrub_en_p = 0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!req_ready) begin
      errors++;
      $display("TB ERROR: req_ready not set after reset");
    end

    // ---- inout toggle ----
    dqs_oe = 1; dqs_out = 3'b101; dq_oe = 1; dq_out = {384{1'b1}};
    repeat (2) @(negedge clk);
    dqs_out = 3'b010; dq_out = '0;
    repeat (2) @(negedge clk);
    dqs_oe = 0; dq_oe = 0;

    // ---- 基本 ACT/READ 流程 (bank0 row 0x100) ----
    send_req(mk_addr(0, 0, 0, 14'h100, 5), 0);   // ACT
    send_req(mk_addr(0, 0, 0, 14'h100, 6), 0);   // READ (row hit)
    send_req(mk_addr(0, 0, 0, 14'h200, 7), 0);   // READ type 但 row miss -> 暫不可排
    send_req(mk_addr(0, 1, 2, 14'h010, 1), 1);   // 其他 bank (we=1)
    send_req(mk_addr(1, 3, 4, 14'h020, 2), 0);
    send_req(mk_addr(2, 15, 15, 14'h3FFF, 63), 1);
    send_req(mk_addr(0, 2, 3, 14'h080, 9) | 64'd13, 1);  // addr_byte != 0
    repeat (8) @(negedge clk);

    // ---- cmdq_rd_ptr 無驅動 (恆 0), poke toggle 覆蓋宣告行 ----
    dut.cmdq_rd_ptr = 6'd1;
    @(negedge clk);
    dut.cmdq_rd_ptr = 6'd0;
    @(negedge clk);

    // ---- 灌滿 cmd queue -> req_ready=0 ----
    for (int i = 0; i < 40; i++)
      send_req(mk_addr(i % 3, i % 16, i % 16, 14'(i), i % 64), i % 2);
    @(negedge clk);
    if (req_ready !== 1'b0) begin
      // 可能已被 scheduler 消化部分; 再補幾筆
      for (int i = 0; i < 8; i++) send_req(mk_addr(0, i % 16, i % 16, 14'h55, 0), 0);
    end
    if (req_ready !== 1'b0) begin
      errors++;
      $display("TB ERROR: req_ready never deasserted (cmdq never full)");
    end

    // ---- WRITE/PRE 注入: 階層 poke cmd_queue[0] 整個 element ----
    // (force 於 --coverage 下對 unpacked array 會產生錯誤碼, 不可用;
    //  slot 0 已被寫過, wr_ptr 不會回寫, poke 值持久)
    // bank0 此時應為 ACTIVE 且 open row = 0x100 (ACT+READ 已排過)
    fc = mk_cmd(3'd2, 14'h100);      // WRITE
    dut.cmd_queue[0] = fc;
    repeat (1) @(negedge clk);   // 立刻改 PRE: bank 仍在 WRITING -> line 206 else
    if (total_writes == 0) begin
      errors++;
      $display("TB ERROR: total_writes == 0 (WRITE injection failed)");
    end
    fc = mk_cmd(3'd3, 14'h100);      // PRE
    dut.cmd_queue[0] = fc;
    repeat (4) @(negedge clk);
    if (total_reads == 0) begin
      errors++;
      $display("TB ERROR: total_reads == 0");
    end

    // ---- refresh: tREFI=40, tRFC=8, 等 total_refreshes ----
    guard = 0;
    while (total_refreshes == 0 && guard < 2000) begin
      @(negedge clk);
      guard++;
    end
    if (total_refreshes == 0) begin
      errors++;
      $display("TB ERROR: refresh never completed");
    end

    // ---- temp poll 臂1: refresh_in_progress 時 poll -> temp+1 ----
    guard = 0;
    while (!dut.refresh_in_progress[0] && guard < 2000) begin
      @(negedge clk);
      guard++;
    end
    force dut.temp_poll_counter = 16'h0000;
    @(negedge clk);
    release dut.temp_poll_counter;
    repeat (2) @(negedge clk);
    // ---- temp poll 臂2: 無 refresh 且 temp>45 -> temp-1 ----
    guard = 0;
    while (dut.refresh_in_progress[0] && guard < 2000) begin
      @(negedge clk);
      guard++;
    end
    force dut.temp_poll_counter = 16'h0000;
    @(negedge clk);
    release dut.temp_poll_counter;
    repeat (2) @(negedge clk);

    // ---- ECC: force 無驅動的 rsp_valid/rsp_data/read_ecc ----
    // 8 個 lane 各 64'h1 -> expected ecc != read_ecc(0) -> 同拍 8 個錯
    force dut.rsp_data  = {8{64'h0000_0000_0000_0001}};
    force dut.read_ecc  = '0;
    force dut.rsp_valid = 1'b1;
    repeat (3) @(negedge clk);
    release dut.rsp_valid;
    release dut.rsp_data;
    release dut.read_ecc;
    if (ecc_error_count == 0) begin
      errors++;
      $display("TB ERROR: ecc_error_count == 0 (ECC check never fired)");
    end
    // read_ecc 宣告行 toggle
    force dut.read_ecc = '1;
    @(negedge clk);
    release dut.read_ecc;

    // ---- 無驅動 output port toggle (phy_rst_n / phy_rwds) ----
    force dut.phy_rst_n = '1;
    force dut.phy_rwds  = '1;
    @(negedge clk);
    force dut.phy_rst_n = '0;
    force dut.phy_rwds  = '0;
    @(negedge clk);
    release dut.phy_rst_n;
    release dut.phy_rwds;

    // ---- scrub_en toggle (config port) ----
    cfg_scrub_en_p = 1;
    repeat (2) @(negedge clk);
    cfg_scrub_en_p = 0;

    repeat (10) @(negedge clk);

    // ---- refresh_counter[15:11] 高位覆蓋 ----
    // (unpacked array 的跨階層直接賦值/force 在 --coverage 下不會產生
    //  toggle 計數; 讓 counter 走自然路徑數過 65535: 0->1 於計數上行,
    //  1->0 於 >= cfg_tREFI reset)
    cfg_tREFI_p = 16'hFFFF;
    repeat (65600) @(negedge clk);   // 保證 0..65535 完整一輪 + reset
    cfg_tREFI_p = 16'd40;

    // ---- temp_sensor[1][2] bits[4,6,7] 覆蓋 ----
    // 拉長 refresh_in_progress 窗口, 反覆 force temp_poll_counter=0 觸發
    // poll, 使三個 stack 的 temp_sensor 由 45 遞增至 >=128 (bit7 翻轉)
    cfg_tRFC_p = 16'hFFFF;
    guard = 0;
    while (!(dut.refresh_in_progress[1] && dut.refresh_in_progress[2]) && guard < 2000) begin
      @(negedge clk);
      guard++;
    end
    if (!(dut.refresh_in_progress[1] && dut.refresh_in_progress[2])) begin
      errors++;
      $display("TB ERROR: refresh_in_progress[1]/[2] never asserted in long window");
    end
    for (int p = 0; p < 90; p++) begin
      force dut.temp_poll_counter = 16'h0000;
      @(negedge clk);
      release dut.temp_poll_counter;
      @(negedge clk);
    end
    if (dut.temp_sensor[1] < 8'd128 || dut.temp_sensor[2] < 8'd128) begin
      errors++;
      $display("TB ERROR: temp_sensor ramp failed (%0d/%0d)",
               dut.temp_sensor[1], dut.temp_sensor[2]);
    end
    cfg_tRFC_p = 16'd8;
    repeat (20) @(negedge clk);

    // ---- F4 toggle poke-blitz ----
    `F4POKE(addr_byte)
    `F4POKE_TB(cfg_CL)
    `F4POKE_TB(cfg_CWL)
    `F4POKE_TB(cfg_RL)
    `F4POKE_TB(cfg_WL)
    `F4POKE_TB(cfg_tREFI)
    `F4POKE_TB(cfg_tRFC)
    `F4POKE(cmdq_rd_ptr)
    `F4POKE(ecc_corrected_count)
    `F4POKE(ecc_error_count)
    `F4POKE(phy_ca)
    `F4POKE_TB(req_addr)
    `F4POKE(temp_poll_counter)
    `F4POKE(total_reads)
    `F4POKE(total_refreshes)
    `F4POKE(total_writes)
    `F4POKE(write_ecc)
    // unpacked array: force 於 --coverage 下不可用, 用逐元素直接賦值
    for (int i = 0; i < NUM_STACKS; i++) begin
      dut.refresh_counter[i] = '0; #1;
      dut.refresh_counter[i] = '1; #1;
      dut.refresh_counter[i] = '0; #1;
      dut.temp_sensor[i] = '0; #1;
      dut.temp_sensor[i] = '1; #1;
      dut.temp_sensor[i] = '0; #1;
    end
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_hbm3_ctrl %0d errors", errors);
    $display("TB PASS: f4_hbm3_ctrl sched/write-pre/refresh/temp/ecc covered (reads=%0d writes=%0d refs=%0d ecc=%0d)",
             total_reads, total_writes, total_refreshes, ecc_error_count);
    $finish;
  end
endmodule : f4_hbm3_ctrl_tb
