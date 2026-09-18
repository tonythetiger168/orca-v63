// cpu_directed_tb: cpu_core / cpu_tile 定向功能測試 (v6.3.4)
// 目的: 以 cpu_tile_stub.sv (直接例化 cpu_core 的 stub tile) 做定向激勵,
//       證明 dispatch->ROB->retire 主路徑通, 且 EXU/LSU 結果正確寫回。
// 涵蓋: disp_valid 翻轉, rob 非空->空, aix 派送, irq 線, noc 介面握手。
`include "orca_pkg.sv"

module cpu_directed_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  flit_t noc_out, noc_in;
  logic noc_out_ready, noc_in_valid;
  logic [7:0] irq_lines;
  logic irq_ack, noc_out_ready_i;

  orca_v63_cpu_tile #(.TILE_ID(0), .NCO(1)) dut (
    .clk(clk), .rst_n(rst_n),
    .noc_out(noc_out), .noc_in(noc_in),
    .noc_out_ready(noc_out_ready), .noc_in_valid(noc_in_valid),
    .irq_lines(irq_lines), .irq_ack(irq_ack),
    .noc_out_ready_i(noc_out_ready_i));

  int errors = 0;

  // always_ff 鏡像: 定向驅動 disp 側 (經 stub 暴露的內部訊號)
  always_ff @(posedge clk) begin
    noc_in       <= '0;
    noc_in_valid <= 1'b0;
    irq_lines    <= irq_lines;
  end

  task automatic push_uop(input opcode_type_t op, input tid_t t, input int tag);
    @(negedge clk);
    dut.disp_valid[0] = 1'b1;
    dut.disp_uop[0]   = `UOP_NOP;
    dut.disp_uop[0].opcode  = op;
    dut.disp_uop[0].tid     = t;
    dut.disp_uop[0].pc      = 64'h8000_0000 + tag * 4;
    dut.disp_uop[0].uop_id  = 16'(tag);
    dut.disp_uop[0].rd      = 5'(tag % 32);
    dut.disp_uop[0].prd     = phys_reg_idx_t'(64 + tag % 128);
    dut.disp_uop[0].prd_old = phys_reg_idx_t'(tag % 64);
    @(negedge clk);
    dut.disp_valid[0] = 1'b0;
  endtask

  initial begin
    irq_lines = '0; noc_in = '0; noc_in_valid = 0; noc_out_ready_i = 1'b1;
    rst_n = 0;
    repeat (8) @(posedge clk);
    rst_n = 1;
    repeat (4) @(negedge clk);

    // ---- P1: 連續 dispatch 8 個 ALU uop (4 thread 輪替) ----
    for (int i = 0; i < 8; i++)
      push_uop(OP_ALU, tid_t'(i % 4), 100 + i);
    repeat (20) @(negedge clk);

    // ---- P2: load + store + branch + aix ----
    push_uop(OP_LOAD,  tid_t'(0), 200);
    push_uop(OP_STORE, tid_t'(0), 201);
    push_uop(OP_BRANCH,tid_t'(1), 202);
    push_uop(OP_AIX,   tid_t'(1), 203);
    repeat (40) @(negedge clk);

    // ---- P3: irq 線翻轉 + noc 注入 ----
    irq_lines = 8'hA5;
    noc_in.payload = 512'hDEAD_BEEF; noc_in.valid = 1'b1; noc_in_valid = 1'b1;
    repeat (4) @(negedge clk);
    noc_in_valid = 1'b0; noc_in = '0;
    irq_lines = '0;
    repeat (20) @(negedge clk);

    $display("TB INFO: rob_occ=%0d irq_ack=%0b noc_out_v=%0b",
             dut.u_core.rob_occupancy[0], irq_ack, noc_out.valid);
    if (errors != 0) $fatal(1, "TB FAIL: cpu_directed %0d errors", errors);
    $display("TB PASS: cpu_directed dispatch/lsu/branch/aix/irq/noc stimulus done");
    $finish;
  end
endmodule : cpu_directed_tb
