// ORCA v6.3.3 coverage TB: pcie_gen6 LTSSM walk + recovery + TLP passthrough
`include "orca_pkg.sv"

module pcie_gen6_cov_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic tx_p, tx_n;
  logic rx_p, rx_n;
  logic refclk_p, refclk_n;
  logic [511:0] tlp_in;
  logic         tlp_in_valid, tlp_in_ready;
  logic [511:0] tlp_out;
  logic         tlp_out_valid;

  // free-running reference clock (unused in stub RTL; cover decl points)
  always #3 refclk_p = ~refclk_p;
  always #3 refclk_n = ~refclk_n;

  pcie_gen6 u_pcie (
    .clk(clk), .rst_n(rst_n),
    .pcie_tx_p(tx_p), .pcie_tx_n(tx_n),
    .pcie_rx_p(rx_p), .pcie_rx_n(rx_n),
    .pcie_refclk_p(refclk_p), .pcie_refclk_n(refclk_n),
    .tlp_in(tlp_in), .tlp_in_valid(tlp_in_valid), .tlp_in_ready(tlp_in_ready),
    .tlp_out(tlp_out), .tlp_out_valid(tlp_out_valid));

  int errors = 0;
  int timeout;

  // FSM 覆蓋監控: 記錄 LTSSM 狀態轉換至 fsm.log
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log","a"); prev = -1;
    forever begin @(posedge clk);
      if (int'(u_pcie.lt) !== prev) begin
        if (prev != -1) $fwrite(fd, "pcie_gen6 %0d %0d\n", prev, int'(u_pcie.lt));
        prev = int'(u_pcie.lt);
      end
    end
  end

  // wait until LTSSM reaches L0 (tx_p=1)
  task automatic wait_l0;
    timeout = 0;
    while (tx_p !== 1'b1 && timeout < 50) begin
      @(negedge clk);
      timeout++;
    end
    if (tx_p !== 1'b1) begin
      errors++; $display("TB FAIL: LTSSM did not reach L0");
    end
  endtask

  initial begin
    rx_p = 1'b0; rx_n = 1'b1;         // no recovery condition
    refclk_p = 1'b0; refclk_n = 1'b1;
    tlp_in = '0; tlp_in_valid = 1'b0;
    rst_n = 0;
    #57 rst_n = 1;

    // DETECT -> POLL -> CONFIG -> L0
    wait_l0();
    #1;
    if (tx_n !== 1'b0) begin
      errors++; $display("TB FAIL: tx_n not complement of tx_p");
    end
    if (tlp_in_ready !== 1'b1) begin
      errors++; $display("TB FAIL: tlp_in_ready low in L0");
    end

    // TLP passthrough in L0
    tlp_in = 512'hCAFE_F00D_1234; tlp_in_valid = 1'b1;
    #1;
    if (tlp_out !== 512'hCAFE_F00D_1234 || tlp_out_valid !== 1'b1) begin
      errors++; $display("TB FAIL: TLP passthrough");
    end
    @(negedge clk);
    tlp_in_valid = 1'b0;
    #1;
    if (tlp_out_valid !== 1'b0) begin
      errors++; $display("TB FAIL: tlp_out_valid stuck");
    end

    // toggle rx_p without triggering recovery (rx_p != rx_n maintained)
    rx_p = 1'b1; rx_n = 1'b0;
    repeat (2) @(negedge clk);
    rx_p = 1'b0; rx_n = 1'b1;
    repeat (2) @(negedge clk);
    if (tx_p !== 1'b1) begin
      errors++; $display("TB FAIL: left L0 on rx_p toggle");
    end

    // force recovery (rx_p == rx_n): L0 -> RECOVERY -> DETECT -> ... -> L0
    rx_n = 1'b0;
    repeat (3) @(negedge clk);
    #1;
    if (tx_p !== 1'b0) begin
      errors++; $display("TB FAIL: LTSSM did not leave L0 on recovery");
    end
    if (tlp_in_ready !== 1'b0) begin
      errors++; $display("TB FAIL: tlp_in_ready high outside L0");
    end
    rx_n = 1'b1;
    wait_l0();

    // TLP again after retraining
    tlp_in = 512'h55; tlp_in_valid = 1'b1;
    #1;
    if (tlp_out_valid !== 1'b1 || tlp_out !== 512'h55) begin
      errors++; $display("TB FAIL: TLP after retrain");
    end
    tlp_in_valid = 1'b0;
    @(negedge clk);

    if (errors != 0) $fatal(1, "TB FAIL: %0d errors", errors);
    $display("TB PASS: pcie_gen6 LTSSM walk + recovery + TLP");
    $finish;
  end
endmodule : pcie_gen6_cov_tb
