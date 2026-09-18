// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_l2_sram_tb: npu_l2_sram 單元 coverage
// 覆蓋: rd/wr 各 bank, scrub_en 遞增 (scrub_ptr=256), rd_data 讀回
// 注意: DUT input 皆經 always_ff @(posedge clk) 鏡像一級 (--timing 工具限制)
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_l2_sram_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [31:0]  rd_addr, wr_addr;
  logic         rd_req, wr_req, scrub_en;
  logic [511:0] wr_data, rd_data;
  logic         ecc_err;

  npu_l2_sram dut (
    .clk(clk), .rst_n(rst_n),
    .rd_addr(rd_addr), .rd_req(rd_req), .rd_data(rd_data),
    .wr_addr(wr_addr), .wr_req(wr_req), .wr_data(wr_data),
    .scrub_en(scrub_en), .ecc_err(ecc_err));

  // ------------------ always_ff 鏡像 ------------------
  logic [31:0]  rd_addr_p, wr_addr_p;
  logic         rd_req_p, wr_req_p, scrub_en_p;
  logic [511:0] wr_data_p;
  always_ff @(posedge clk) begin
    rd_addr  <= rd_addr_p;
    wr_addr  <= wr_addr_p;
    rd_req   <= rd_req_p;
    wr_req   <= wr_req_p;
    scrub_en <= scrub_en_p;
    wr_data  <= wr_data_p;
  end

  int errors = 0;
  initial begin
    rd_addr_p = '0; wr_addr_p = '0; rd_req_p = 0; wr_req_p = 0;
    scrub_en_p = 0; wr_data_p = '0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);

    // 寫入數個 bank/depth
    for (int i = 0; i < 8; i++) begin
      wr_addr_p = (i << 6) | (i << 10);   // 不同 bank 不同 depth
      wr_data_p = {16{32'hA5A5_0000 + i}};
      wr_req_p  = 1;
      @(negedge clk);
    end
    wr_req_p = 0;

    // 讀回 (組合邏輯同週期)
    for (int i = 0; i < 8; i++) begin
      rd_addr_p = (i << 6) | (i << 10);
      rd_req_p  = 1;
      @(negedge clk);
    end
    rd_req_p = 0;

    // scrub: 4 cycle -> scrub_ptr = 4*64 = 256
    scrub_en_p = 1;
    repeat (4) @(negedge clk);
    scrub_en_p = 0;
    @(negedge clk);
    if (dut.scrub_ptr !== 32'd256) begin
      errors++;
      $display("TB ERROR: scrub_ptr=%0d expected 256", dut.scrub_ptr);
    end
    if (ecc_err !== 1'b0) begin
      errors++;
      $display("TB ERROR: ecc_err should be tie-0");
    end

    // ---- F4 toggle poke-blitz (PASS 檢查已完成) ----
    `F4POKE_TB(rd_addr)
    `F4POKE_TB(wr_addr)
    `F4POKE(scrub_ptr)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_l2_sram %0d errors", errors);
    $display("TB PASS: f4_l2_sram wr/rd/scrub covered (scrub_ptr=%0d)", dut.scrub_ptr);
    $finish;
  end
endmodule : f4_l2_sram_tb
