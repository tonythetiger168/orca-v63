// ORCA v6.3.4 coverage TB: orca_flit_adapter
// v6.3.4 fix BUG-C: adapter 退化為直通 — pkg flit_t (525b) 完整標頭進出線網,
// 每個 flit (含 BODY/TAIL) 逐位守恆; 檢查雙向直通與 ready/valid 對接。
`include "orca_pkg.sv"

module orca_flit_adapter_cov_tb;
  import orca_pkg::*;
  localparam int FW = $bits(flit_t);   // v6.3.4 fix BUG-C: 512 -> 525
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  flit_t t_out;
  logic  t_out_ready;
  flit_t t_in;
  logic  t_in_valid, t_in_ready;
  logic [FW-1:0] r_rx_data;
  logic          r_rx_valid, r_rx_ready;
  logic [FW-1:0] r_tx_data;
  logic          r_tx_valid, r_tx_ready;

  orca_flit_adapter u_adapt (
    .clk(clk), .rst_n(rst_n),
    .t_out(t_out), .t_out_ready(t_out_ready),
    .t_in(t_in), .t_in_valid(t_in_valid), .t_in_ready(t_in_ready),
    .r_rx_data(r_rx_data), .r_rx_valid(r_rx_valid), .r_rx_ready(r_rx_ready),
    .r_tx_data(r_tx_data), .r_tx_valid(r_tx_valid), .r_tx_ready(r_tx_ready));

  int errors = 0;

  // TX 方向: tile -> 線網直通, 全 flit 完整標頭守恆 (head/body/tail/single 同構)
  task automatic check_out(input flit_type_t ft);
    t_out         = '0;
    t_out.valid   = 1'b1;
    t_out.ftype   = ft;
    t_out.dest_x  = 2'd1;
    t_out.dest_y  = 2'd2;
    t_out.src_x   = 2'd3;
    t_out.src_y   = 2'd0;
    t_out.vc_id   = 2'd2;
    t_out.payload = 512'hDEAD_BEEF_CAFE_1234;
    r_rx_ready    = 1'b1;
    #1;
    if (r_rx_valid !== 1'b1) begin
      errors++; $display("TB FAIL: r_rx_valid low for ftype %0d", ft);
    end
    if (t_out_ready !== 1'b1) begin
      errors++; $display("TB FAIL: t_out_ready != r_rx_ready");
    end
    // v6.3.4 fix BUG-C: 直通 — 線網位元 = pkg flit_t 位元 (含 dest/vc/ftype/valid)
    if (r_rx_data !== FW'(t_out)) begin
      errors++; $display("TB FAIL: r_rx_data != t_out passthrough for ftype %0d", ft);
    end
    begin
      flit_t wf;
      wf = flit_t'(r_rx_data);
      if (wf.dest_x !== 2'd1 || wf.vc_id !== 2'd2 || wf.valid !== 1'b1) begin
        errors++; $display("TB FAIL: header fields not on wire for ftype %0d", ft);
      end
    end
  endtask

  initial begin
    t_out = '0; r_rx_ready = 1'b0;
    r_tx_data = '0; r_tx_valid = 1'b0; t_in_ready = 1'b0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (2) @(negedge clk);

    // TX direction: all four flit types (每 flit 皆帶完整標頭直通)
    check_out(FLIT_HEAD);
    check_out(FLIT_SINGLE);
    check_out(FLIT_BODY);
    check_out(FLIT_TAIL);

    // Backpressure passthrough on TX side
    r_rx_ready = 1'b0;
    #1;
    if (t_out_ready !== 1'b0) begin
      errors++; $display("TB FAIL: t_out_ready should follow r_rx_ready=0");
    end
    r_rx_ready = 1'b1;

    // RX direction: 線網 -> tile 直通, flit_t 完整還原 (含 dest/vc/ftype)
    begin
      flit_t rf;
      rf         = '0;
      rf.valid   = 1'b1;
      rf.ftype   = FLIT_TAIL;
      rf.dest_x  = 2'd2;
      rf.dest_y  = 2'd1;
      rf.src_x   = 2'd0;
      rf.src_y   = 2'd1;
      rf.vc_id   = 2'd3;
      rf.payload = 512'h1234_ABCD;
      r_tx_data  = FW'(rf);
    end
    r_tx_valid = 1'b1;
    t_in_ready = 1'b1;
    #1;
    if (t_in_valid !== 1'b1 || t_in.valid !== 1'b1) begin
      errors++; $display("TB FAIL: t_in_valid/t_in.valid low");
    end
    if (t_in.payload !== 512'h1234_ABCD) begin
      errors++; $display("TB FAIL: t_in.payload mismatch");
    end
    // v6.3.4 fix BUG-C: 標頭欄位直接來自線網, 不再重建 FLIT_SINGLE
    if (t_in.ftype !== FLIT_TAIL || t_in.dest_x !== 2'd2 || t_in.vc_id !== 2'd3) begin
      errors++; $display("TB FAIL: t_in header fields mismatch");
    end
    if (r_tx_ready !== 1'b1) begin
      errors++; $display("TB FAIL: r_tx_ready != t_in_ready");
    end
    t_in_ready = 1'b0;
    #1;
    if (r_tx_ready !== 1'b0) begin
      errors++; $display("TB FAIL: r_tx_ready should follow t_in_ready=0");
    end
    // r_tx_valid 拉低時 t_in.valid 跟隨 (直通以握手 valid 為準)
    r_tx_valid = 1'b0;
    t_out.valid = 1'b0;
    #1;
    if (r_rx_valid !== 1'b0 || t_in_valid !== 1'b0 || t_in.valid !== 1'b0) begin
      errors++; $display("TB FAIL: valids should be low when idle");
    end

    if (errors != 0) $fatal(1, "TB FAIL: %0d errors", errors);
    $display("TB PASS: orca_flit_adapter passthrough both directions + backpressure");
    $finish;
  end
endmodule : orca_flit_adapter_cov_tb
