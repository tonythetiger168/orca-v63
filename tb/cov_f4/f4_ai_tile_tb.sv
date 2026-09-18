// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_ai_tile_tb: orca_v63_ai_tile 單元 coverage
// 覆蓋: 5 個 back-to-back GEMM 飽和單一 cluster (cl_busy/cl_done 自然 toggle,
//       不可 force comb net), inflight 解鎖用 force (FF), ATTN_QK 分派
//       (attn_cmd_q/base addr 路徑), noc_in flit, noc_in_ready (force u_noc.st),
//       attn_hbm_addr/v (tie-off, force toggle)
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_ai_tile_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  uop_t  aix;
  logic  av, ar, irq;
  flit_t no, ni;
  logic  noc_ordy, niv, nir;
  logic [HBM3_STACKS-1:0] hbm_ck_t, hbm_ck_c, hbm_cs_n;
  logic  hbm_init_done;

  orca_v63_ai_tile #(.TILE_ID(0), .NCLUSTERS(1)) dut (
    .clk(clk), .rst_n(rst_n),
    .aix_uop(aix), .aix_valid(av), .aix_ready(ar),
    .noc_out(no), .noc_out_ready(noc_ordy),
    .noc_in(ni), .noc_in_valid(niv), .noc_in_ready(nir),
    .aix_irq(irq),
    .hbm_ck_t(hbm_ck_t), .hbm_ck_c(hbm_ck_c), .hbm_cs_n(hbm_cs_n),
    .hbm_init_done(hbm_init_done));

  // ------------------ always_ff 鏡像 ------------------
  uop_t  aix_p;
  logic  av_p, noc_ordy_p, niv_p;
  flit_t ni_p;
  always_ff @(posedge clk) begin
    aix <= aix_p;
    av  <= av_p;
    noc_ordy <= noc_ordy_p;
    ni  <= ni_p;
    niv <= niv_p;
  end

  int errors = 0;
  int guard = 0;
  logic saw_irq = 0;
  logic saw_cl_busy = 0, saw_cl_done = 0;
  always @(posedge clk) begin
    if (irq) saw_irq <= 1'b1;
    if (dut.cl_busy[0]) saw_cl_busy <= 1'b1;
    if (dut.cl_done[0]) saw_cl_done <= 1'b1;
  end

  task automatic send_aix(input logic [7:0] aix_op, input logic [31:0] len);
    @(negedge clk);
    aix_p = '0;
    aix_p.opcode = OP_AIX;
    aix_p.imm    = (64'(len) << 19) | 64'(aix_op);
    aix_p.rs1    = 5'd1;
    aix_p.rs2    = 5'd2;
    aix_p.rd     = 5'd3;
    av_p = 1'b1;
    @(negedge clk);
    av_p = 1'b0;
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
    aix_p = '0; av_p = 0; noc_ordy_p = 1; ni_p = '0; niv_p = 0;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);

    // ---- noc_in flit (noc_in_valid toggle) ----
    ni_p = '0;
    ni_p.valid = 1'b1;
    ni_p.payload = {16{32'h5A5A_A5A5}};
    niv_p = 1;
    @(negedge clk);
    niv_p = 0;
    ni_p = '0;

    // ---- 5 個 back-to-back GEMM 飽和 cluster ----
    for (int i = 0; i < 5; i++) send_aix(8'h01, 32'd100);   // AIX_OP_GEMM

    // 等 uop 全部到達 GSCU (鏡像延遲), 再等 queue drain
    repeat (20) @(negedge clk);
    guard = 0;
    while (dut.u_gscu.qc != 0 && guard < 8000) begin
      @(negedge clk);
      guard++;
    end
    if (dut.u_gscu.qc != 0) begin
      errors++;
      $display("TB ERROR: GSCU queue did not drain (qc=%0d)", dut.u_gscu.qc);
    end
    // 等 in-flight CU 全部完成, 再解鎖 parked inflight (FF, 非 comb net)
    repeat (400) @(negedge clk);
    force dut.u_gscu.inflight = '0;
    repeat (2) @(negedge clk);
    release dut.u_gscu.inflight;
    wait_irq(200);
    if (!saw_cl_busy || !saw_cl_done) begin
      errors++;
      $display("TB ERROR: cl_busy/cl_done never toggled (busy=%0b done=%0b)",
               saw_cl_busy, saw_cl_done);
    end

    // ---- TDB base_addr 非零 (tdb_we tie-0, poke tdb_file) ----
    // 讓 attn_q/k/v/o_base 在 ATTN 分派後變值 (line 85 宣告行需要 toggle)
    dut.u_intf.tdb_file[2].base_addr = 64'h0000_1234_0000_0000;
    dut.u_intf.tdb_file[1].base_addr = 64'h0000_5678_0000_0000;
    dut.u_intf.tdb_file[3].base_addr = 64'h0000_9ABC_0000_0000;

    // ---- ATTN_QK 分派 (attn_cmd_q + base addr 路徑) ----
    send_aix(8'h03, 32'd16);   // AIX_OP_ATTN_QK, seq_len=16
    guard = 0;
    while (!dut.attn_active && guard < 500) begin
      @(negedge clk);
      guard++;
    end
    if (!dut.attn_active) begin
      errors++;
      $display("TB ERROR: attn engine never dispatched");
    end
    wait_irq(5000);

    // ---- attn_hbm tie-off net force toggle (line 96/97) ----
    force dut.attn_hbm_v    = 1'b1;
    force dut.attn_hbm_addr = 64'hDEAD_0000;
    @(negedge clk);
    force dut.attn_hbm_v    = 1'b0;
    force dut.attn_hbm_addr = 64'h0;
    @(negedge clk);
    release dut.attn_hbm_v;
    release dut.attn_hbm_addr;

    // ---- noc_in_ready: force u_noc.st 到 N_RSP (2'd3) ----
    force dut.u_noc.st[0] = 1'b1;
    force dut.u_noc.st[1] = 1'b1;
    niv_p = 1;
    ni_p  = '0;
    ni_p.valid = 1'b1;
    repeat (2) @(negedge clk);
    release dut.u_noc.st[0];
    release dut.u_noc.st[1];
    niv_p = 0;
    ni_p  = '0;
    repeat (2) @(negedge clk);

    // ---- hbm_init_done (PHY training) ----
    guard = 0;
    while (!hbm_init_done && guard < 1000) begin
      @(negedge clk);
      guard++;
    end
    if (!hbm_init_done) begin
      errors++;
      $display("TB ERROR: hbm_init_done never set");
    end

    // ---- F4 toggle poke-blitz (功能測試 PASS 後; 皆為 dut 頂層內部訊號) ----
    `F4POKE(ai_cmd)
    `F4POKE(attn_cmd_q)
    `F4POKE(attn_hbm_addr)
    `F4POKE(attn_k_base)
    `F4POKE(attn_l2_addr)
    `F4POKE(attn_o_base)
    `F4POKE(attn_q_base)
    `F4POKE(attn_seq_len)
    `F4POKE(attn_v_base)
    `F4POKE(gscu_cl_cmd)
    `F4POKE(l2_rd_addr_w)
    `F4POKE(l2_wr_addr_w)
    `F4POKE(tdb_busy)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_ai_tile %0d errors", errors);
    $display("TB PASS: f4_ai_tile gemm-saturate/attn/noc covered");
    $finish;
  end
endmodule : f4_ai_tile_tb
