// ORCA v6.3 ZEN++ - v6.3.3
// f1_cpu_tile_tb: cov-f1 tile 級 smoke TB
// 目標: rtl/cpu/orca_v63_cpu_tile.sv line coverage 100%
// 策略: 以 NCO=1 例化 tile (glue line 覆蓋與核心數無關, 且省記憶體),
//       core 的 L2 fill 以 hierarchical 寫入 undriven 的 dut.l2_line /
//       dut.l2_fill_v 注入 (風格同 cpu_directed_tb 的 force 注入),
//       讓核心取指推進使 l2_addr/l2_v toggle;
//       irq_lines / noc_in / noc_in_valid / noc_out_ready_i 由 TB 驅動 toggle;
//       恆定訊號 (noc_out=FLIT_EMPTY, halt_all=core tie-0) 以 force/release
//       注入 toggle (任務允許之防禦性恆定訊號, 不更動 RTL)。
`include "orca_pkg.sv"

module f1_cpu_tile_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  flit_t       noc_in;
  logic        noc_in_valid;
  logic [7:0]  irq_lines;
  logic        noc_out_ready_i;
  flit_t       noc_out;
  logic        noc_out_ready, irq_ack;

  orca_v63_cpu_tile #(.TILE_ID(0), .NCO(1)) dut (
    .clk(clk), .rst_n(rst_n),
    .noc_out(noc_out), .noc_in(noc_in),
    .noc_out_ready(noc_out_ready), .noc_in_valid(noc_in_valid),
    .irq_lines(irq_lines), .irq_ack(irq_ack),
    .noc_out_ready_i(noc_out_ready_i));

  int errors = 0;

  // 餵 core 的 L2 fill 程式 (同 cpu_directed_tb): 全 x0 來源, 保證管線活動
  localparam logic [31:0] PROG [8] = '{
    32'h0200_0093, 32'h0400_0113, 32'h0200_01B3, 32'h0200_0233,
    32'h0000_2023, 32'h0000_2283, 32'h0000_0333, 32'h0200_2023
  };

  // l2_line / l2_fill_v 在 tile 內無 driver (undriven), TB 直接寫入注入 fill
  always @(negedge clk) begin
    if (rst_n) begin
      dut.l2_fill_v = dut.l2_v[0];
      if (dut.l2_v[0])
        for (int w = 0; w < 16; w++)
          dut.l2_line[w*32 +: 32] = PROG[w % 8];
    end
  end

  initial begin
    noc_in = '0; noc_in_valid = 0; irq_lines = 8'h00; noc_out_ready_i = 0;
    repeat (5) @(negedge clk);
    rst_n = 1;

    // ---- 核心跑 400 拍 (l2_addr/l2_v 自然 toggle) ----
    repeat (400) @(negedge clk);

    // ---- port toggle: irq / noc_in / noc_out_ready_i ----
    irq_lines = 8'hFF; noc_in_valid = 1; noc_in = '1; noc_out_ready_i = 1;
    @(negedge clk);
    if (!irq_ack) begin $display("ERROR: irq_lines!=0 時 irq_ack 應為 1"); errors++; end
    irq_lines = 8'h55; noc_in = '0; noc_out_ready_i = 0;
    @(negedge clk);
    irq_lines = 8'h00; noc_in_valid = 0;
    @(negedge clk);
    if (irq_ack) begin $display("ERROR: irq_lines==0 時 irq_ack 應為 0"); errors++; end
    if (!noc_out_ready) begin $display("ERROR: noc_out_ready 應恆 1"); errors++; end

    // ---- 恆定訊號 force-toggle (noc_out=FLIT_EMPTY, halt_all=core tie 0) ----
    force dut.noc_out = '1;
    @(negedge clk);
    force dut.noc_out = '0;
    @(negedge clk);
    release dut.noc_out;
    force dut.halt_all = 1'b1;
    @(negedge clk);
    force dut.halt_all = 1'b0;
    @(negedge clk);
    release dut.halt_all;

    repeat (4) @(negedge clk);
    if (errors == 0) $display("TB PASS: f1_cpu_tile_tb (orca_v63_cpu_tile)");
    else             $display("TB FAIL: f1_cpu_tile_tb errors=%0d", errors);

    // ---- cov-f1 toggle: l2_addr[0] 零命中 bits ----
    // l2_addr 由 core l2_req_addr (= icache miss_addr = fetch_pc = u_fetch.pc_n)
    // 驅動, module-output 線網 poke 不生效 (F5 經驗); 改 poke 驅動源頭 FF
    // u_fetch.pc_r, comb 鏈於 settle 傳播使 l2_addr[0] 真實翻動。
    // 注意: pc_n = pc_r + FETCH_WIDTH*4 (fetch_ack 時), poke '1 會 wrap 成
    // 64'h1F, 中間位永遠不會出現在 l2_addr — 故改用 hFFFF_FFFF_FFFF_C01F:
    // bit[4:0]=1 (覆低 5 bit), bit[14:63]=1 (覆中高位), 且 +32 進位僅到
    // bit5, 上述 bits 在 ack/非 ack 兩種情況下都保持 1; 再 poke 0 形成 1->0。
    dut.g_core[0].u_core.u_fetch.pc_r = 64'hFFFF_FFFF_FFFF_C01F; #1;
    dut.g_core[0].u_core.u_fetch.pc_r = 64'h0; #1;
    repeat (3) @(negedge clk);
    $finish;
  end
endmodule : f1_cpu_tile_tb
