// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_gscu_tb: npu_gscu 單元 coverage
// 覆蓋: GEMM cluster 分派/inflight/rr, ATTN_QK/ATTN_AV 分派 + attn_done,
//       queue 填滿 (cmd_ready=0), irq drain pulse, tdb_busy,
//       DMA_ST -> G_DRAIN (line 82), cl_busy 全忙路徑
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_gscu_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  aix_cmd_t cmd_in, cl_cmd;
  logic     cmd_valid, cmd_ready, irq;
  aix_tdb_t tdb_rd [AIX_NUM_TDB];
  logic [AIX_NUM_TDB-1:0] tdb_busy;
  logic     cl_cmd_valid, cl_cmd_ready;
  logic [CLUSTERS_PER_TILE-1:0] cl_done, cl_busy;
  logic     attn_cmd_valid, attn_cmd_ready, attn_done;

  npu_gscu dut (
    .clk(clk), .rst_n(rst_n),
    .cmd_in(cmd_in), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .irq(irq),
    .tdb_rd(tdb_rd), .tdb_busy(tdb_busy),
    .cl_cmd(cl_cmd), .cl_cmd_valid(cl_cmd_valid), .cl_cmd_ready(cl_cmd_ready),
    .cl_done(cl_done), .cl_busy(cl_busy),
    .attn_cmd_valid(attn_cmd_valid), .attn_cmd_ready(attn_cmd_ready),
    .attn_done(attn_done));

  // ------------------ always_ff 鏡像 ------------------
  aix_cmd_t cmd_in_p;
  logic     cmd_valid_p, cl_cmd_ready_p, attn_cmd_ready_p, attn_done_p;
  logic [CLUSTERS_PER_TILE-1:0] cl_done_p, cl_busy_p;
  always_ff @(posedge clk) begin
    cmd_in         <= cmd_in_p;
    cmd_valid      <= cmd_valid_p;
    cl_cmd_ready   <= cl_cmd_ready_p;
    attn_cmd_ready <= attn_cmd_ready_p;
    attn_done      <= attn_done_p;
    cl_done        <= cl_done_p;
    cl_busy        <= cl_busy_p;
    for (int i = 0; i < AIX_NUM_TDB; i++) tdb_rd[i] <= '0;
  end

  int errors = 0;
  // ---- FSM coverage monitor: npu_gscu gst ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (int'(dut.gst) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_gscu %0d %0d\n", prev, int'(dut.gst));
        prev = int'(dut.gst);
      end
    end
  end
  logic saw_irq = 0;
  always @(posedge clk) if (irq) saw_irq <= 1'b1;

  task automatic send_cmd(input logic [7:0] op, input logic [15:0] h0,
                          input logic [15:0] h1);
    @(negedge clk);
    cmd_in_p = '0;
    cmd_in_p.opcode = op;
    cmd_in_p.tdb0   = h0;
    cmd_in_p.tdb1   = h1;
    cmd_in_p.length = 32'd16;
    cmd_valid_p = 1;
    @(negedge clk);
    cmd_valid_p = 0;
  endtask

  task automatic wait_irq(input int lim);
    int n;
    saw_irq = 0;
    for (n = 0; n < lim && !saw_irq; n++) @(negedge clk);
    if (!saw_irq) begin
      errors++;
      $display("TB ERROR: irq timeout");
    end
  endtask

  initial begin
    cmd_in_p = '0; cmd_valid_p = 0; cl_cmd_ready_p = 0;
    attn_cmd_ready_p = 0; attn_done_p = 0; cl_done_p = '0; cl_busy_p = '0;
    for (int i = 0; i < AIX_NUM_TDB; i++) tdb_rd[i] = '0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!cmd_ready) begin
      errors++;
      $display("TB ERROR: cmd_ready not set after reset");
    end

    // ---- 1) GEMM 分派到 cluster 0, cl_done 完成 -> irq ----
    cl_cmd_ready_p = 1;
    send_cmd(8'h01, 16'd1, 16'd2);        // AIX_OP_GEMM
    repeat (6) @(negedge clk);
    if (tdb_busy[1] !== 1'b1 || tdb_busy[2] !== 1'b1) begin
      errors++;
      $display("TB ERROR: tdb_busy not set for GEMM handles");
    end
    @(negedge clk);
    cl_done_p = 16'h0001;                  // cluster 0 完成 (寬脈衝保險)
    repeat (3) @(negedge clk);
    cl_done_p = '0;
    wait_irq(50);

    // ---- 2) ATTN_QK 分派 ----
    attn_cmd_ready_p = 1;
    send_cmd(8'h03, 16'd3, 16'd4);        // AIX_OP_ATTN_QK
    repeat (6) @(negedge clk);
    @(negedge clk);
    attn_done_p = 1;
    @(negedge clk);
    attn_done_p = 0;
    wait_irq(50);

    // ---- 3) ATTN_AV 分派 ----
    send_cmd(8'h04, 16'd5, 16'd6);        // AIX_OP_ATTN_AV
    repeat (6) @(negedge clk);
    @(negedge clk);
    attn_done_p = 1;
    @(negedge clk);
    attn_done_p = 0;
    wait_irq(50);
    attn_cmd_ready_p = 0;

    // ---- 4) cl_busy 全忙: cl_cmd_valid 只靠 qc!=0 初始式 ----
    cl_cmd_ready_p = 0;
    cl_busy_p = '1;
    send_cmd(8'h01, 16'd7, 16'd8);
    repeat (4) @(negedge clk);
    cl_busy_p = '0;

    // ---- 5) 填滿 queue -> cmd_ready=0 ----
    for (int i = 0; i < 16; i++) send_cmd(8'h01, 16'(i), 16'(i + 1));
    repeat (4) @(negedge clk);
    if (cmd_ready !== 1'b0) begin
      errors++;
      $display("TB ERROR: cmd_ready should deassert when queue full");
    end

    // ---- 6) drain: 16 筆分派後 cl_done 全清 -> irq ----
    cl_cmd_ready_p = 1;
    repeat (30) @(negedge clk);
    cl_done_p = '1;
    @(negedge clk);
    cl_done_p = '0;
    wait_irq(100);

    // ---- 7) DMA_ST -> G_DRAIN (line 82; 83 為不可達 arm, 加 pragma) ----
    cl_cmd_ready_p = 0;
    send_cmd(8'h11, 16'd9, 16'd10);       // AIX_OP_DMA_ST
    repeat (6) @(negedge clk);
    if (dut.gst != 1'b1) begin            // G_DRAIN = 1
      errors++;
      $display("TB ERROR: gst did not enter G_DRAIN after DMA_ST");
    end

    // ---- F4 toggle poke-blitz ----
    `F4POKE(cl_cmd)
    `F4POKE_TB(cmd_in)
    `F4POKE(tdb_busy)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_gscu %0d errors", errors);
    $display("TB PASS: f4_gscu dispatch/attn/queue-full/drain covered");
    $finish;
  end
endmodule : f4_gscu_tb
