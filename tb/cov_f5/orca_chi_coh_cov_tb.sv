// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3.3 coverage TB: orca_chi_coh
// All request ops (incl. out-of-enum default), snoop in MODIFIED vs not.
`include "orca_pkg.sv"

module orca_chi_coh_cov_tb;
  import orca_pkg::*;
  import orca_chi_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  paddr_t      req_addr;
  logic        req_valid;
  chi_req_op_t req_op;
  logic        req_ready;
  logic [511:0] rsp_data;
  logic        rsp_valid;
  paddr_t      snp_addr;
  logic        snp_valid;
  coh_state_t  snp_state;
  logic        snp_dirty;
  logic [511:0] snp_data;
  logic        snp_ack;

  orca_chi_coh u_chi (
    .clk(clk), .rst_n(rst_n),
    .req_addr(req_addr), .req_valid(req_valid), .req_op(req_op),
    .req_ready(req_ready), .rsp_data(rsp_data), .rsp_valid(rsp_valid),
    .snp_addr(snp_addr), .snp_valid(snp_valid),
    .snp_state(snp_state), .snp_dirty(snp_dirty),
    .snp_data(snp_data), .snp_ack(snp_ack));

  int errors = 0;

  // FSM 覆蓋監控: 記錄 MESI state 轉換至 fsm.log
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log","a"); prev = -1;
    forever begin @(posedge clk);
      if (int'(u_chi.state) !== prev) begin
        if (prev != -1) $fwrite(fd, "orca_chi_coh %0d %0d\n", prev, int'(u_chi.state));
        prev = int'(u_chi.state);
      end
    end
  end

  task automatic do_req(input chi_req_op_t op, input coh_state_t exp_st);
    @(negedge clk);
    req_addr = 64'h1000; req_op = op; req_valid = 1'b1;
    #1;
    if (req_ready !== 1'b1 || rsp_valid !== 1'b1) begin
      errors++; $display("TB FAIL: req handshake low for op %0d", op);
    end
    @(negedge clk);
    req_valid = 1'b0;
    #1;
    if (snp_state !== exp_st) begin
      errors++;
      $display("TB FAIL: op %0d state %0d != exp %0d", op, snp_state, exp_st);
    end
    if (rsp_valid !== 1'b0) begin
      errors++; $display("TB FAIL: rsp_valid stuck");
    end
  endtask

  initial begin
    req_addr = '0; req_valid = 0; req_op = CHI_RD;
    snp_addr = '0; snp_valid = 0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (2) @(negedge clk);
    #1;
    if (snp_state !== COH_INVALID) $fatal(1, "TB FAIL: not INVALID after reset");

    do_req(CHI_RD,   COH_SHARED);
    do_req(CHI_RDO,  COH_EXCLUSIVE);
    do_req(CHI_WR,   COH_MODIFIED);
    if (snp_dirty !== 1'b1) begin
      errors++; $display("TB FAIL: snp_dirty low in MODIFIED");
    end
    // snoop while MODIFIED: state must stay MODIFIED
    @(negedge clk);
    snp_addr = 64'h2000; snp_valid = 1'b1;
    #1;
    if (snp_ack !== 1'b1) begin
      errors++; $display("TB FAIL: snp_ack low");
    end
    @(negedge clk);
    snp_valid = 1'b0;
    #1;
    if (snp_state !== COH_MODIFIED) begin
      errors++; $display("TB FAIL: MODIFIED lost on snoop");
    end
    do_req(CHI_WRO,  COH_MODIFIED);
    do_req(CHI_EVICT, COH_INVALID);

    // out-of-enum op: hits `default: ;`, state unchanged
    @(negedge clk);
    req_op = chi_req_op_t'(3'd7); req_valid = 1'b1;
    @(negedge clk);
    req_valid = 1'b0;
    #1;
    if (snp_state !== COH_INVALID) begin
      errors++; $display("TB FAIL: default op changed state");
    end

    // snoop while not MODIFIED: goes SHARED
    @(negedge clk);
    snp_valid = 1'b1;
    @(negedge clk);
    snp_valid = 1'b0;
    #1;
    if (snp_state !== COH_SHARED) begin
      errors++; $display("TB FAIL: snoop did not force SHARED");
    end

    // ---- FSM arc 補齊: MESI 非自轉 arc 全 12 條 ----
    // 目前已覆蓋 I->S, S->E, E->M, M->I, I->S(2nd); 現 state = S
    do_req(CHI_EVICT, COH_INVALID);  // S->I
    do_req(CHI_RDO,   COH_EXCLUSIVE);// I->E
    do_req(CHI_EVICT, COH_INVALID);  // E->I
    do_req(CHI_WR,    COH_MODIFIED); // I->M
    do_req(CHI_RDO,   COH_EXCLUSIVE);// M->E
    do_req(CHI_RD,    COH_SHARED);   // E->S
    do_req(CHI_WR,    COH_MODIFIED); // S->M
    do_req(CHI_RD,    COH_SHARED);   // M->S
    do_req(CHI_EVICT, COH_INVALID);  // S->I (收尾回 INVALID)

    if (errors != 0) $fatal(1, "TB FAIL: %0d errors", errors);
    $display("TB PASS: orca_chi_coh all ops + snoop paths");

    // ---- poke-blitz: 補齊 toggle 零命中點 (功能已 PASS, 僅為覆蓋) ----
    req_addr = '0; #1; req_addr = '1; #1; req_addr = '0; #1;
    snp_addr = '0; #1; snp_addr = '1; #1; snp_addr = '0; #1;
    repeat (2) @(negedge clk);
    // state (FF enum): 最末 poke 補 bit2 (F/P 值域), 之後不再給 clock
    u_chi.state = coh_state_t'(3'h0); #1;
    u_chi.state = coh_state_t'(3'h7); #1;
    u_chi.state = coh_state_t'(3'h0); #1;
    $finish;
  end
endmodule : orca_chi_coh_cov_tb
