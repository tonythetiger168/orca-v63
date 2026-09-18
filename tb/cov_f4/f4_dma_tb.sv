// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_dma_tb: npu_dma 單元 coverage
// 覆蓋: DMA_LD / DMA_ST descriptor, D_IDLE->D_XFER->D_LAST->D_IDLE,
//       hbm_ack stall/前進, default arm (逐 bit force 無效 state)
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_dma_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  aix_cmd_t desc;
  logic     desc_valid, desc_ready, done;
  logic [31:0] l2_addr;
  logic        l2_req, l2_we;
  logic [511:0] l2_rdata, l2_wdata;
  paddr_t      hbm_addr;
  logic        hbm_req, hbm_we;
  logic [511:0] hbm_rdata, hbm_wdata;
  logic        hbm_ack;

  npu_dma dut (
    .clk(clk), .rst_n(rst_n),
    .desc(desc), .desc_valid(desc_valid), .desc_ready(desc_ready),
    .done(done),
    .l2_addr(l2_addr), .l2_req(l2_req), .l2_rdata(l2_rdata),
    .l2_wdata(l2_wdata), .l2_we(l2_we),
    .hbm_addr(hbm_addr), .hbm_req(hbm_req), .hbm_we(hbm_we),
    .hbm_rdata(hbm_rdata), .hbm_wdata(hbm_wdata), .hbm_ack(hbm_ack));

  // ------------------ always_ff 鏡像 ------------------
  aix_cmd_t desc_p;
  logic     desc_valid_p, hbm_ack_p;
  logic [511:0] l2_rdata_p, hbm_rdata_p;
  always_ff @(posedge clk) begin
    desc       <= desc_p;
    desc_valid <= desc_valid_p;
    hbm_ack    <= hbm_ack_p;
    l2_rdata   <= l2_rdata_p;
    hbm_rdata  <= hbm_rdata_p;
  end

  int errors = 0;
  bit fsm_mute = 0;         // force st 期間靜音 FSM monitor
  // ---- FSM coverage monitor: npu_dma st ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (fsm_mute) prev = int'(dut.st);
      else if (int'(dut.st) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_dma %0d %0d\n", prev, int'(dut.st));
        prev = int'(dut.st);
      end
    end
  end
  logic saw_done = 0;
  always @(posedge clk) if (done) saw_done <= 1'b1;

  // 發一個 descriptor, length 以 64B beat 計
  task automatic send_desc(input logic [7:0] op, input logic [31:0] len);
    @(negedge clk);
    desc_p = '0;
    desc_p.opcode  = op;
    desc_p.tdb0    = 16'h00AA;
    desc_p.tdb1    = 16'h00BB;
    desc_p.length  = len;
    desc_valid_p = 1;
    @(negedge clk);
    desc_valid_p = 0;
  endtask

  initial begin
    desc_p = '0; desc_valid_p = 0; hbm_ack_p = 0;
    l2_rdata_p = {16{32'h1111_2222}}; hbm_rdata_p = {16{32'h3333_4444}};
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!desc_ready) begin
      errors++;
      $display("TB ERROR: desc_ready not set after reset");
    end

    // ---- DMA_LD (is_ld=1 -> l2_we/hbm_we=1), len=128 -> 2 beats ----
    send_desc(AIX_OP_DMA_LD, 32'd128);
    // stall 2 cycle (hbm_ack=0, D_XFER 等待)
    repeat (2) @(negedge clk);
    if (!l2_req || !hbm_req) begin
      errors++;
      $display("TB ERROR: l2_req/hbm_req not asserted in D_XFER");
    end
    // ack 3 次, 完成 xfer
    hbm_ack_p = 1;
    repeat (3) @(negedge clk);
    hbm_ack_p = 0;
    repeat (4) @(negedge clk);
    if (!saw_done) begin
      errors++;
      $display("TB ERROR: DMA_LD never reached D_LAST/done");
    end

    // ---- DMA_ST (is_ld=0), len=64 -> 1 beat ----
    send_desc(AIX_OP_DMA_ST, 32'd64);
    repeat (2) @(negedge clk);
    hbm_ack_p = 1;
    repeat (2) @(negedge clk);
    hbm_ack_p = 0;
    repeat (4) @(negedge clk);

    // default arm: 逐 bit force st 到無效值 2'd3
    fsm_mute = 1;
    force dut.st[0] = 1'b1;
    force dut.st[1] = 1'b1;
    @(negedge clk);
    release dut.st[0];
    release dut.st[1];
    @(negedge clk);
    @(negedge clk);   // fsm_mon 於 posedge 采樣的是 NBA 更新前的舊值,
                      // 多等一拍讓 prev 在靜音中跟上 0, 避免記到假弧 3->0
    fsm_mute = 0;
    if (dut.st != 2'd0) begin   // D_IDLE = 0 (enum 在 DUT 內, TB 以數值比對)
      errors++;
      $display("TB ERROR: default arm did not return to D_IDLE");
    end

    // ---- F4 toggle poke-blitz ----
    `F4POKE(cnt)
    `F4POKE_TB(desc)
    `F4POKE(hbm_addr)
    `F4POKE(l2_addr)
    `F4POKE(len)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_dma %0d errors", errors);
    $display("TB PASS: f4_dma LD/ST descriptor flow covered");
    $finish;
  end
endmodule : f4_dma_tb
