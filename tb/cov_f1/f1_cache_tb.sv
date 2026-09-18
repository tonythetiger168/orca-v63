// ORCA v6.3 ZEN++ - v6.3.3
// f1_cache_tb: cov-f1 單元級 directed TB
// 目標: dcache.sv / icache.sv / l2cache.sv / l3cache.sv line coverage 100%
// 策略: 四個 cache 共用同一組 stimulus (位址映射設計成對 SETS=128/SW=7/WAYS=8
//       與 SETS=512/SW=9/WAYS=16 皆落在同一 set), 打遍:
//         miss+fill / read hit / victim loop 兩方向 / 全 way valid 後 return 0 /
//         writeback (wb_valid) / write hit (req_wmask 部分遮罩兩方向) /
//         所有 input port bit toggle (含未使用的 fill_valid/fill_dirty)。
`include "orca_pkg.sv"

module f1_cache_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // 共享 stimulus
  paddr_t       req_addr;
  logic         req_valid;
  logic         miss_ack;
  logic [511:0] fill_line;
  logic         fill_valid, fill_dirty;
  xword_t       req_wdata;
  logic [7:0]   req_wmask;

  // dcache
  logic d_ready, d_hit, d_miss_v, d_wb_v;
  xword_t d_rdata; paddr_t d_miss_a, d_wb_a; logic [511:0] d_wb_l;
  dcache u_dcache (.clk(clk), .rst_n(rst_n), .req_addr(req_addr),
    .req_valid(req_valid), .req_ready(d_ready), .hit(d_hit),
    .req_rdata(d_rdata), .req_wdata(req_wdata), .req_wmask(req_wmask),
    .miss_addr(d_miss_a), .miss_valid(d_miss_v), .miss_ack(miss_ack),
    .fill_line(fill_line), .fill_valid(fill_valid), .fill_dirty(fill_dirty),
    .wb_valid(d_wb_v), .wb_addr(d_wb_a), .wb_line(d_wb_l));

  // icache (無 write port)
  logic i_ready, i_hit, i_miss_v, i_wb_v;
  xword_t i_rdata; paddr_t i_miss_a, i_wb_a; logic [511:0] i_wb_l;
  icache u_icache (.clk(clk), .rst_n(rst_n), .req_addr(req_addr),
    .req_valid(req_valid), .req_ready(i_ready), .hit(i_hit),
    .req_rdata(i_rdata),
    .miss_addr(i_miss_a), .miss_valid(i_miss_v), .miss_ack(miss_ack),
    .fill_line(fill_line), .fill_valid(fill_valid), .fill_dirty(fill_dirty),
    .wb_valid(i_wb_v), .wb_addr(i_wb_a), .wb_line(i_wb_l));

  // l2cache
  logic l2_ready, l2_hit, l2_miss_v, l2_wb_v;
  xword_t l2_rdata; paddr_t l2_miss_a, l2_wb_a; logic [511:0] l2_wb_l;
  l2cache u_l2 (.clk(clk), .rst_n(rst_n), .req_addr(req_addr),
    .req_valid(req_valid), .req_ready(l2_ready), .hit(l2_hit),
    .req_rdata(l2_rdata), .req_wdata(req_wdata), .req_wmask(req_wmask),
    .miss_addr(l2_miss_a), .miss_valid(l2_miss_v), .miss_ack(miss_ack),
    .fill_line(fill_line), .fill_valid(fill_valid), .fill_dirty(fill_dirty),
    .wb_valid(l2_wb_v), .wb_addr(l2_wb_a), .wb_line(l2_wb_l));

  // l3cache
  logic l3_ready, l3_hit, l3_miss_v, l3_wb_v;
  xword_t l3_rdata; paddr_t l3_miss_a, l3_wb_a; logic [511:0] l3_wb_l;
  l3cache u_l3 (.clk(clk), .rst_n(rst_n), .req_addr(req_addr),
    .req_valid(req_valid), .req_ready(l3_ready), .hit(l3_hit),
    .req_rdata(l3_rdata), .req_wdata(req_wdata), .req_wmask(req_wmask),
    .miss_addr(l3_miss_a), .miss_valid(l3_miss_v), .miss_ack(miss_ack),
    .fill_line(fill_line), .fill_valid(fill_valid), .fill_dirty(fill_dirty),
    .wb_valid(l3_wb_v), .wb_addr(l3_wb_a), .wb_line(l3_wb_l));

  int errors = 0;
  // wb_valid 監測旗標 (combinationl 訊號, 於週期中採樣)
  logic wb_seen_d = 0, wb_seen_i = 0, wb_seen_l2 = 0, wb_seen_l3 = 0;
  always @(d_wb_v)  if (d_wb_v)  wb_seen_d  = 1;
  always @(i_wb_v)  if (i_wb_v)  wb_seen_i  = 1;
  always @(l2_wb_v) if (l2_wb_v) wb_seen_l2 = 1;
  always @(l3_wb_v) if (l3_wb_v) wb_seen_l3 = 1;
  // BASE: addr[20:12] 固定 => dcache(SW=7,set=a[18:12]) 與 l2/l3(SW=9,set=a[20:12])
  // 皆同 set; tag 用 addr[63:21] 變化 (dcache tag=a[63:19] 亦不同)。
  localparam paddr_t BASE = 64'h0000_0000_0003_0000; // set=48 (addr[20:12]=0x30), tag bits [63:21] 乾淨

  function automatic logic [511:0] line_pat(input int k);
    logic [511:0] p;
    for (int w = 0; w < 8; w++)
      p[w*64 +: 64] = (k % 3 == 0) ? 64'hFFFF_FFFF_FFFF_FFFF :
                      (k % 3 == 1) ? 64'h0000_0000_0000_0000 :
                                     (64'h1 << (w*8 + k)) * 64'h0101_0101_0101_0101;
    return p;
  endfunction

  initial begin
    req_addr = '0; req_valid = 0; miss_ack = 0;
    fill_line = '0; fill_valid = 0; fill_dirty = 0;
    req_wdata = '0; req_wmask = '0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // ---- 未使用 input toggle: fill_valid / fill_dirty ----
    fill_valid = 1; fill_dirty = 1; @(negedge clk);
    fill_valid = 0; fill_dirty = 0; @(negedge clk);

    // ---- Phase 1: 17 次 miss+fill 同 set 不同 tag ----
    //  dcache/icache: 8 way 滿後 victim()->0 (全 valid) => wb_valid=1
    //  l2/l3: 16 way 滿後同樣; victim loop 兩方向皆覆蓋
    for (int k = 0; k < 17; k++) begin
      req_addr  = BASE | (paddr_t'(k) << 21);
      req_valid = 1; miss_ack = 1;
      fill_line = line_pat(k);
      @(negedge clk);
    end
    // wb_valid 在「全 way valid 後的 miss」當拍為 1 (combinationl), 此處於
    // fill 週期中段 (#1) 採樣 (k=8 起 dcache/icache 滿 8 way; k=16 起 l2/
l3 滿 16 way)
    if (!wb_seen_d)  begin $display("ERROR: dcache wb_valid 未拉起"); errors++; end
    if (!wb_seen_i)  begin $display("ERROR: icache wb_valid 未拉起"); errors++; end
    if (!wb_seen_l2) begin $display("ERROR: l2cache wb_valid 未拉起"); errors++; end
    if (!wb_seen_l3) begin $display("ERROR: l3cache wb_valid 未拉起"); errors++; end

    // ---- Phase 2: read hit (變化 offset), 檢查 hit ----
    miss_ack = 0;
    for (int k = 1; k < 8; k++) begin
      req_addr  = BASE | (paddr_t'(k) << 21) | ((k & 7) << 3);
      req_valid = 1;
      #1;
      if (k >= 2 && !d_hit)  begin $display("ERROR: dcache k=%0d 應 hit", k); errors++; end
      if (k >= 2 && !l2_hit) begin $display("ERROR: l2cache k=%0d 應 hit", k); errors++; end
      @(negedge clk);
    end

    // ---- Phase 3: write hit (dcache/l2/l3): wmask 兩方向 ----
    // read hit (tag k=3 仍在 way3) -> 下一拍 hit_q=1 時下 wmask
    req_addr = BASE | (paddr_t'(3) << 21); req_valid = 1; req_wmask = 8'h00; @(negedge clk);
    req_wmask = 8'h0F; req_wdata = 64'hF0F0_F0F0_F0F0_F0F0; @(negedge clk);
    req_addr = BASE | (paddr_t'(3) << 21); req_wmask = 8'h00; @(negedge clk); // re-hit
    req_wmask = 8'hF0; req_wdata = 64'h0F0F_0F0F_0F0F_0F0F; @(negedge clk);
    req_wmask = 8'h00;
    // readback check dcache
    req_addr = BASE | (paddr_t'(3) << 21); req_valid = 1; #1;
    begin
      logic [63:0] exp_lo, exp_hi;
      exp_lo = line_pat(3); exp_hi = line_pat(3);
      for (int b = 0; b < 4; b++) exp_lo[b*8 +: 8] = 8'hF0;
      for (int b = 4; b < 8; b++) exp_hi[b*8 +: 8] = 8'h0F;
      if (d_rdata[31:0]  !== exp_lo[31:0])  begin $display("ERROR: dcache wb lo %h != %h", d_rdata[31:0], exp_lo[31:0]); errors++; end
      if (d_rdata[63:32] !== exp_hi[63:32]) begin $display("ERROR: dcache wb hi %h != %h", d_rdata[63:32], exp_hi[63:32]); errors++; end
    end
    @(negedge clk);

    // ---- Phase 4: miss 不 ack (miss_valid 但無 fill) + idle ----
    req_addr = BASE | (paddr_t'(63) << 21); req_valid = 1; miss_ack = 0; @(negedge clk);
    req_valid = 0; @(negedge clk);

    // ---- Phase 5: 全 bit toggle 風暴 (所有 input 兩方向) ----
    for (int k = 0; k < 3; k++) begin
      req_addr = 64'hFFFF_FFFF_FFFF_FFFF; req_wdata = '1; req_wmask = 8'hFF;
      fill_line = '1; fill_valid = 1; fill_dirty = 1;
      req_valid = 1; miss_ack = 1; @(negedge clk);
      req_addr = '0; req_wdata = '0; req_wmask = 8'h00;
      fill_line = '0; fill_valid = 0; fill_dirty = 0;
      req_valid = 0; miss_ack = 0; @(negedge clk);
      req_addr = 64'hAAAA_AAAA_AAAA_AAAA; req_wdata = 64'hAAAA_AAAA_AAAA_AAAA;
      req_wmask = 8'hAA; fill_line = {8{64'hAAAA_AAAA_AAAA_AAAA}};
      req_valid = 1; miss_ack = 1; @(negedge clk);
      req_addr = 64'h5555_5555_5555_5555; req_wdata = 64'h5555_5555_5555_5555;
      req_wmask = 8'h55; fill_line = {8{64'h5555_5555_5555_5555}};
      req_valid = 1; miss_ack = 0; @(negedge clk);
    end

    // ---- Phase 6 (cov-f1 toggle): writeback 位址高位功能性翻動 ----
    // set48 全 way valid (Phase 1 已填滿), victim() 恆回 way0。
    // 依序 fill tag=0 -> 全1 tag -> tag0, eviction 當拍 wb_addr =
    // {被逐 tag, set, 12'b0}, 使 wb_addr[63:12] 真實 0->1->0 翻動。
    // A1: set48 (dcache addr[18:12]/l2l3 addr[20:12] 皆 48), l2/l3 tag 全1,
    //     dcache tag[44:2] 全1; A2: dcache set48 且 tag[1:0]=11 (dcache 全1)。
    begin
      localparam paddr_t A1 = 64'hFFFF_FFFF_FFE3_0000;
      localparam paddr_t A2 = 64'hFFFF_FFFF_FFFB_0000;
      req_addr = BASE; req_valid = 1; miss_ack = 1; @(negedge clk); // evict way0, fill tag0
      req_addr = A1; @(negedge clk);   // wb=tag0;        fill A1tag
      req_addr = BASE; @(negedge clk); // wb=A1tag (0->1); fill tag0
      req_addr = A2; @(negedge clk);   // wb=tag0 (1->0); fill A2tag (dcache 全1)
      req_addr = BASE; @(negedge clk); // wb=A2tag (0->1); fill tag0
      req_addr = A2;   @(negedge clk); // wb=tag0 (1->0)
      req_addr = BASE; @(negedge clk);
      req_valid = 0; miss_ack = 0; @(negedge clk);
    end

    // ---- 第二次 reset (rst_n 1->0->1) ----
    rst_n = 0; repeat (2) @(negedge clk);
    rst_n = 1; repeat (2) @(negedge clk);

    if (errors == 0) $display("TB PASS: f1_cache_tb (dcache/icache/l2cache/l3cache)");
    else             $display("TB FAIL: f1_cache_tb errors=%0d", errors);

    $finish;
  end
endmodule : f1_cache_tb
