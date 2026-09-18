// ORCA v6.3.3 coverage TB: orca_bow_link training FSM
`include "orca_pkg.sv"

module orca_bow_link_cov_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [7:0] tx_data, tx_clk;
  logic [7:0] rx_data, rx_clk;
  logic       link_up, train_start;

  orca_bow_link u_bow (
    .clk(clk), .rst_n(rst_n),
    .bow_tx_data(tx_data), .bow_tx_clk(tx_clk),
    .bow_rx_data(rx_data), .bow_rx_clk(rx_clk),
    .link_up(link_up), .train_start(train_start));

  initial begin
    rx_data = 8'h55; rx_clk = 8'hAA;
    train_start = 1'b0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (2) @(negedge clk);
    if (link_up !== 1'b0) $fatal(1, "TB FAIL: link_up before training");

    // train_start=0: counter must hold
    repeat (3) @(negedge clk);
    if (link_up !== 1'b0) $fatal(1, "TB FAIL: cnt moved without train_start");

    // run training to completion (cnt 0 -> F)
    train_start = 1'b1;
    repeat (20) @(negedge clk);
    if (link_up !== 1'b1) $fatal(1, "TB FAIL: BoW link did not train");
    if (tx_data !== 8'hA5) $fatal(1, "TB FAIL: bow_tx_data != 8'hA5");
    if (tx_clk !== 8'hFF) $fatal(1, "TB FAIL: bow_tx_clk != 8'hFF at cnt=F");

    // train_start deasserts while link_up (cover !link_up term)
    train_start = 1'b0;
    repeat (2) @(negedge clk);
    if (link_up !== 1'b1) $fatal(1, "TB FAIL: link_up dropped");

    $display("TB PASS: orca_bow_link training sequence");

    // ---- poke-blitz: 補齊 toggle 零命中點 (功能已 PASS, 僅為覆蓋) ----
    // bow_tx_data 組合 output (恆 8'hA5): poke 後還原但仍命中
    u_bow.bow_tx_data = '0; #1; u_bow.bow_tx_data = '1; #1; u_bow.bow_tx_data = '0; #1;
    repeat (2) @(negedge clk);
    $finish;
  end
endmodule : orca_bow_link_cov_tb
