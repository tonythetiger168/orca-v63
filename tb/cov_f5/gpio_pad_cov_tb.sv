// ORCA v6.3.3 coverage TB: gpio_pad (drive / pull-up / hi-z + input path)
`include "orca_pkg.sv"

module gpio_pad_cov_tb;
  import orca_pkg::*;

  logic [31:0] o, i, oe, pu, ds;
  tri   [31:0] pad;
  // external driver emulating the outside world
  logic [31:0] ext_drv, ext_oe;
  assign pad = ext_oe ? ext_drv : 32'hzzzz_zzzz;

  gpio_pad u_gpio (
    .gpio_o(o), .gpio_i(i), .gpio_oe(oe),
    .gpio_pu(pu), .gpio_ds(ds), .pad(pad));

  int errors = 0;

  initial begin
    ext_drv = '0; ext_oe = '0;
    ds = '0;

    // 1) output enable: pad follows gpio_o
    o = 32'hA5A5_5A5A; oe = '1; pu = '0;
    #1;
    if (pad !== 32'hA5A5_5A5A || i !== 32'hA5A5_5A5A) begin
      errors++; $display("TB FAIL: output drive path");
    end
    o = 32'h5A5A_A5A5;
    #1;
    if (pad !== 32'h5A5A_A5A5 || i !== 32'h5A5A_A5A5) begin
      errors++; $display("TB FAIL: output drive toggle");
    end

    // 2) oe=0, pu=1: weak pull-up to 1
    oe = '0; pu = '1;
    #1;
    if (pad !== 32'hFFFF_FFFF || i !== 32'hFFFF_FFFF) begin
      errors++; $display("TB FAIL: pull-up path");
    end

    // 3) oe=0, pu=0: hi-z, external driver wins (input path)
    pu = '0; ext_oe = '1; ext_drv = 32'h1234_5678;
    #1;
    if (i !== 32'h1234_5678) begin
      errors++; $display("TB FAIL: input path");
    end
    ext_drv = 32'h0;
    #1;
    if (i !== 32'h0) begin
      errors++; $display("TB FAIL: input path low");
    end

    // 4) mixed per-bit config: even bits driven, odd bits pulled up
    ext_oe = '0;
    o = 32'h5555_5555; oe = 32'h5555_5555; pu = 32'hAAAA_AAAA;
    #1;
    if (pad !== 32'hFFFF_FFFF) begin
      errors++; $display("TB FAIL: mixed oe/pu, pad=%h", pad);
    end

    // 5) toggle gpio_ds (unused in stub RTL; cover its declaration point)
    ds = '1; #1; ds = 32'h5555_AAAA; #1; ds = '0; #1;

    if (errors != 0) $fatal(1, "TB FAIL: %0d errors", errors);
    $display("TB PASS: gpio_pad drive/pullup/hiz/input paths");
    $finish;
  end
endmodule : gpio_pad_cov_tb
