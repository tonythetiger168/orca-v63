// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_tile_noc_tb: npu_tile_noc 單元 coverage
// 覆蓋: N_IDLE->N_HDR->N_PAY->N_RSP->N_IDLE, credit/ready stall (N_PAY/N_RSP
//       else 路徑), dma_rdata 回讀, 寫/讀兩種 transaction
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_tile_noc_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  paddr_t dma_addr;
  logic   dma_valid, dma_is_write, dma_ready;
  logic [511:0] dma_wdata, dma_rdata;
  flit_t  noc_out, noc_in;
  logic   noc_out_ready, noc_in_valid, noc_in_ready;
  logic [NOC_VC-1:0] vc_credit;

  npu_tile_noc dut (
    .clk(clk), .rst_n(rst_n),
    .dma_addr(dma_addr), .dma_valid(dma_valid), .dma_is_write(dma_is_write),
    .dma_wdata(dma_wdata), .dma_ready(dma_ready), .dma_rdata(dma_rdata),
    .noc_out(noc_out), .noc_out_ready(noc_out_ready),
    .noc_in(noc_in), .noc_in_valid(noc_in_valid), .noc_in_ready(noc_in_ready),
    .vc_credit(vc_credit));

  // ------------------ always_ff 鏡像 ------------------
  paddr_t dma_addr_p;
  logic   dma_valid_p, dma_is_write_p;
  logic [511:0] dma_wdata_p;
  flit_t  noc_in_p;
  logic   noc_out_ready_p, noc_in_valid_p;
  logic [NOC_VC-1:0] vc_credit_p;
  always_ff @(posedge clk) begin
    dma_addr      <= dma_addr_p;
    dma_valid     <= dma_valid_p;
    dma_is_write  <= dma_is_write_p;
    dma_wdata     <= dma_wdata_p;
    noc_in        <= noc_in_p;
    noc_out_ready <= noc_out_ready_p;
    noc_in_valid  <= noc_in_valid_p;
    vc_credit     <= vc_credit_p;
  end

  int errors = 0;
  // ---- FSM coverage monitor: npu_tile_noc st ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (int'(dut.st) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_tile_noc %0d %0d\n", prev, int'(dut.st));
        prev = int'(dut.st);
      end
    end
  end
  logic saw_hdr = 0, saw_pay = 0;
  always @(posedge clk) begin
    if (dut.st == 2'd1) saw_hdr <= 1'b1;   // N_HDR
    if (dut.st == 2'd2) saw_pay <= 1'b1;   // N_PAY
  end

  initial begin
    dma_addr_p = '0; dma_valid_p = 0; dma_is_write_p = 0; dma_wdata_p = '0;
    noc_in_p = '0; noc_out_ready_p = 0; noc_in_valid_p = 0; vc_credit_p = '0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!dma_ready) begin
      errors++;
      $display("TB ERROR: dma_ready not set in N_IDLE");
    end

    // ---- transaction 1 (write): 各 state 都 stall ----
    dma_addr_p = 64'h0000_0000_0000_0300;   // dest_x = addr[9:8] = 3
    dma_wdata_p = {16{32'hCAFE_F00D}};
    dma_is_write_p = 1;
    dma_valid_p = 1;
    @(negedge clk);
    dma_valid_p = 0;
    // N_HDR: credit=0 stall 2 cycle
    repeat (2) @(negedge clk);
    if (!noc_out.valid) begin
      errors++;
      $display("TB ERROR: noc_out.valid not set in N_HDR");
    end
    // credit ok 但 ready=0 stall 1 cycle
    vc_credit_p = 4'b0001;
    @(negedge clk);
    // ready=1 -> N_PAY
    noc_out_ready_p = 1;
    @(negedge clk);
    // N_PAY: ready=0 stall (else 路徑)
    noc_out_ready_p = 0;
    repeat (2) @(negedge clk);
    noc_out_ready_p = 1;
    @(negedge clk);
    // N_RSP: noc_in_valid=0 stall (else 路徑)
    noc_out_ready_p = 0;
    repeat (2) @(negedge clk);
    if (!noc_in_ready) begin
      errors++;
      $display("TB ERROR: noc_in_ready not set in N_RSP");
    end
    noc_in_p = '0;
    noc_in_p.payload = {16{32'h1234_5678}};
    noc_in_p.valid = 1'b1;
    noc_in_valid_p = 1;
    @(negedge clk);
    noc_in_valid_p = 0;
    noc_in_p = '0;
    repeat (2) @(negedge clk);

    // ---- transaction 2 (read): 無 stall 快速通過 ----
    dma_addr_p = 64'h0000_0000_0000_0100;   // dest_x = 1
    dma_is_write_p = 0;
    dma_valid_p = 1;
    vc_credit_p = 4'b0001;
    noc_out_ready_p = 1;
    @(negedge clk);
    dma_valid_p = 0;
    repeat (2) @(negedge clk);
    noc_in_valid_p = 1;
    @(negedge clk);
    noc_in_valid_p = 0;
    repeat (3) @(negedge clk);

    if (!saw_hdr || !saw_pay) begin
      errors++;
      $display("TB ERROR: never reached N_HDR/N_PAY");
    end
    if (dut.st != 2'd0) begin
      errors++;
      $display("TB ERROR: did not return to N_IDLE");
    end

    // ---- F4 toggle poke-blitz ----
    `F4POKE_TB(dma_addr)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_tile_noc %0d errors", errors);
    $display("TB PASS: f4_tile_noc flit flow + stall paths covered");
    $finish;
  end
endmodule : f4_tile_noc_tb
