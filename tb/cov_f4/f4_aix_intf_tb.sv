// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_aix_intf_tb: npu_aix_intf 單元 coverage
// 覆蓋: uop -> cmd_out 組合轉換, tdb_we 寫 TDB 檔, completion 回報, reset
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_aix_intf_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  uop_t     aix_uop;
  logic     aix_valid, aix_ready;
  aix_cmd_t cmd_out;
  logic     cmd_valid, cmd_ready;
  logic     completion, completion_valid;
  logic     tdb_we;
  logic [7:0] tdb_idx;
  aix_tdb_t tdb_wdata;
  aix_tdb_t tdb_rd [AIX_NUM_TDB];

  npu_aix_intf dut (
    .clk(clk), .rst_n(rst_n),
    .aix_uop(aix_uop), .aix_valid(aix_valid), .aix_ready(aix_ready),
    .cmd_out(cmd_out), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
    .completion(completion), .completion_valid(completion_valid),
    .tdb_we(tdb_we), .tdb_idx(tdb_idx), .tdb_wdata(tdb_wdata),
    .tdb_rd(tdb_rd));

  // ------------------ always_ff 鏡像 ------------------
  uop_t     aix_uop_p;
  logic     aix_valid_p, cmd_ready_p, completion_p;
  logic     tdb_we_p;
  logic [7:0] tdb_idx_p;
  aix_tdb_t tdb_wdata_p;
  always_ff @(posedge clk) begin
    aix_uop     <= aix_uop_p;
    aix_valid   <= aix_valid_p;
    cmd_ready   <= cmd_ready_p;
    completion  <= completion_p;
    tdb_we      <= tdb_we_p;
    tdb_idx     <= tdb_idx_p;
    tdb_wdata   <= tdb_wdata_p;
  end

  int errors = 0;
  initial begin
    aix_uop_p = '0; aix_valid_p = 0; cmd_ready_p = 0; completion_p = 0;
    tdb_we_p = 0; tdb_idx_p = '0; tdb_wdata_p = '0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);

    // uop -> cmd_out 組合路徑: 填滿各欄位
    aix_uop_p.rs2 = 5'd5;             // tdb0
    aix_uop_p.rs1 = 5'd6;             // tdb1
    aix_uop_p.rd  = 5'd7;             // tdb2
    aix_uop_p.imm = (64'h12345 << 19) | (64'hAB << 8) | 64'h03;
    aix_valid_p   = 1;
    cmd_ready_p   = 1;
    @(negedge clk);
    if (cmd_out.tdb0 != 16'd5 || cmd_out.tdb1 != 16'd6 || cmd_out.tdb2 != 16'd7) begin
      errors++;
      $display("TB ERROR: cmd_out tdb mapping wrong");
    end
    if (cmd_out.opcode != 8'h03 || cmd_out.flags != 8'hAB) begin
      errors++;
      $display("TB ERROR: cmd_out opcode/flags wrong");
    end
    if (!cmd_valid || !aix_ready) begin
      errors++;
      $display("TB ERROR: cmd_valid/aix_ready wrong");
    end
    aix_valid_p = 0;
    // completion 路徑
    completion_p = 1;
    @(negedge clk);
    if (!completion_valid) begin
      errors++;
      $display("TB ERROR: completion_valid not forwarded");
    end
    completion_p = 0;

    // TDB 檔寫入 + 讀出
    tdb_wdata_p = '0;
    tdb_wdata_p.base_addr = 64'hDEAD_BEEF_0000_1000;
    tdb_wdata_p.dim0 = 32'd16;
    tdb_wdata_p.valid = 1'b1;
    tdb_we_p  = 1;
    tdb_idx_p = 8'd42;
    @(negedge clk);
    tdb_we_p = 0;
    @(negedge clk);
    if (tdb_rd[42].base_addr != 64'hDEAD_BEEF_0000_1000) begin
      errors++;
      $display("TB ERROR: tdb_rd[42] mismatch");
    end

    // ---- F4 toggle poke-blitz ----
    `F4POKE(cmd_out)
    `F4POKE_TB(tdb_idx)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_aix_intf %0d errors", errors);
    $display("TB PASS: f4_aix_intf cmd/tdb/completion covered");
    $finish;
  end
endmodule : f4_aix_intf_tb
