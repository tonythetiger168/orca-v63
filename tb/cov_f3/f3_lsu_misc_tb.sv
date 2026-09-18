// ORCA v6.3 ZEN++ - coverage TB (agent f3b)
// f3_lsu_misc_tb: lsu_mshr / lsu_dtlb / lsu_dcache(+dcache) 單元 coverage
// 注意: Verilator 5.006 --timing 下, 由 initial coroutine 直接驅動的 TB 訊號
// 不會產生子模組 port 連線賦值 (工具限制), 故所有 DUT 輸入皆經 always_ff
// @(posedge clk) 鏡像一級 (_p -> 實際訊號)。
// 時序模型: cycle k negedge 設定的值, cycle k+1 對 DUT 可見,
// DUT 在 cycle k+1 結尾的 posedge 採樣 (cycle k+2 生效)。
`include "orca_pkg.sv"

module f3_lsu_misc_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  int errors = 0;

  // ======================= lsu_mshr =======================
  paddr_t     m_req_addr;
  logic       m_req_valid, m_req_is_store;
  logic       m_req_accept;
  mshr_idx_t  m_req_idx;
  logic       m_miss_full;
  logic       m_fill_valid;
  paddr_t     m_fill_addr;
  logic [MSHR_ENTRIES-1:0] m_complete;
  paddr_t     m_complete_addr [MSHR_ENTRIES];
  logic       m_retire_entry;
  mshr_idx_t  m_retire_idx;
  logic       m_wb_req;
  paddr_t     m_wb_addr;

  lsu_mshr u_mshr (
    .clk(clk), .rst_n(rst_n),
    .req_addr(m_req_addr), .req_valid(m_req_valid), .req_is_store(m_req_is_store),
    .req_accept(m_req_accept), .req_idx(m_req_idx), .miss_full(m_miss_full),
    .fill_valid(m_fill_valid), .fill_addr(m_fill_addr),
    .complete(m_complete), .complete_addr(m_complete_addr),
    .retire_entry(m_retire_entry), .retire_idx(m_retire_idx),
    .wb_req(m_wb_req), .wb_addr(m_wb_addr));

  // ======================= lsu_dtlb =======================
  xword_t  t_va;
  logic    t_q_valid, t_hit;
  paddr_t  t_pa;
  logic    t_walk_req;
  xword_t  t_walk_addr;
  logic    t_walk_rvalid;
  xword_t  t_walk_rdata;
  logic    t_fill_valid;
  xword_t  t_fill_va;
  paddr_t  t_fill_pa;

  lsu_dtlb u_dt (
    .clk(clk), .rst_n(rst_n),
    .va(t_va), .q_valid(t_q_valid), .hit(t_hit), .pa(t_pa),
    .walk_req(t_walk_req), .walk_addr(t_walk_addr),
    .walk_rvalid(t_walk_rvalid), .walk_rdata(t_walk_rdata),
    .fill_valid(t_fill_valid), .fill_va(t_fill_va), .fill_pa(t_fill_pa));

  // ======================= lsu_dcache (+dcache) =======================
  paddr_t      d_req_addr;
  logic        d_req_valid, d_req_we;
  xword_t      d_req_wdata;
  logic [7:0]  d_req_wmask;
  logic        d_req_ready;
  xword_t      d_req_rdata;
  logic        d_req_hit;
  paddr_t      d_miss_addr;
  logic        d_miss_valid;
  logic        d_miss_ack;
  logic [511:0] d_fill_line;
  logic        d_fill_valid;
  logic        d_wb_valid;
  paddr_t      d_wb_addr;
  logic [511:0] d_wb_line;
  logic        d_stbuf_empty;

  lsu_dcache u_dc (
    .clk(clk), .rst_n(rst_n),
    .req_addr(d_req_addr), .req_valid(d_req_valid), .req_we(d_req_we),
    .req_wdata(d_req_wdata), .req_wmask(d_req_wmask),
    .req_ready(d_req_ready), .req_rdata(d_req_rdata), .req_hit(d_req_hit),
    .miss_addr(d_miss_addr), .miss_valid(d_miss_valid), .miss_ack(d_miss_ack),
    .fill_line(d_fill_line), .fill_valid(d_fill_valid),
    .wb_valid(d_wb_valid), .wb_addr(d_wb_addr), .wb_line(d_wb_line),
    .stbuf_empty(d_stbuf_empty));

  // ------------------ always_ff 鏡像 ------------------
  paddr_t     m_req_addr_p2;
  logic       m_req_valid_p, m_req_is_store_p, m_fill_valid_p;
  paddr_t     m_fill_addr_p;
  logic       m_retire_entry_p;
  mshr_idx_t  m_retire_idx_p;
  xword_t  t_va_p;
  logic    t_q_valid_p, t_walk_rvalid_p;
  xword_t  t_walk_rdata_p;
  logic    t_fill_valid_p;
  xword_t  t_fill_va_p;
  paddr_t  t_fill_pa_p;
  paddr_t      d_req_addr_p;
  logic        d_req_valid_p, d_req_we_p;
  xword_t      d_req_wdata_p;
  logic [7:0]  d_req_wmask_p;
  logic        d_miss_ack_p;
  logic [511:0] d_fill_line_p;
  logic        d_fill_valid_p;

  always_ff @(posedge clk) begin
    m_req_addr    <= m_req_addr_p2;
    m_req_valid   <= m_req_valid_p;
    m_req_is_store<= m_req_is_store_p;
    m_fill_valid  <= m_fill_valid_p;
    m_fill_addr   <= m_fill_addr_p;
    m_retire_entry<= m_retire_entry_p;
    m_retire_idx  <= m_retire_idx_p;
    t_va          <= t_va_p;
    t_q_valid     <= t_q_valid_p;
    t_walk_rvalid <= t_walk_rvalid_p;
    t_walk_rdata  <= t_walk_rdata_p;
    t_fill_valid  <= t_fill_valid_p;
    t_fill_va     <= t_fill_va_p;
    t_fill_pa     <= t_fill_pa_p;
    d_req_addr    <= d_req_addr_p;
    d_req_valid   <= d_req_valid_p;
    d_req_we      <= d_req_we_p;
    d_req_wdata   <= d_req_wdata_p;
    d_req_wmask   <= d_req_wmask_p;
    d_miss_ack    <= d_miss_ack_p;
    d_fill_line   <= d_fill_line_p;
    d_fill_valid  <= d_fill_valid_p;
  end

  // ======================= MSHR tasks =======================
  // alloc 一筆 (1 cycle req_valid)
  task automatic m_alloc(input logic [63:0] addr, input logic is_st);
    @(negedge clk);
    m_req_valid_p = 1;  m_req_addr_p2 = addr;  m_req_is_store_p = is_st;
    @(negedge clk);
    m_req_valid_p = 0;
  endtask

  task automatic m_fill(input logic [63:0] addr);
    @(negedge clk);
    m_fill_valid_p = 1;  m_fill_addr_p = addr;
    @(negedge clk);
    m_fill_valid_p = 0;
  endtask

  task automatic m_retire(input int idx);
    @(negedge clk);
    m_retire_entry_p = 1;  m_retire_idx_p = mshr_idx_t'(idx);
    @(negedge clk);
    m_retire_entry_p = 0;
  endtask

  // ======================= DTLB tasks =======================
  task automatic t_fill(input logic [63:0] va, input logic [63:0] pa);
    @(negedge clk);
    t_fill_valid_p = 1;  t_fill_va_p = va;  t_fill_pa_p = pa;
    @(negedge clk);
    t_fill_valid_p = 0;
  endtask

  // query 1 cycle (組合 hit, 但維持 q_valid 1 cycle)
  task automatic t_query(input logic [63:0] va);
    @(negedge clk);
    t_va_p = va;  t_q_valid_p = 1;
    @(negedge clk);
    t_q_valid_p = 0;
  endtask

  // ======================= dcache tasks =======================
  // read: 回傳是否 hit (於第二個 negedge 採樣組合輸出)
  task automatic d_read(input logic [63:0] addr, output logic was_hit);
    @(negedge clk);
    d_req_valid_p = 1;  d_req_we_p = 0;  d_req_addr_p = addr;
    @(negedge clk);                       // 訊號可見, 組合輸出已穩定
    was_hit = d_req_hit;
    @(negedge clk);
    d_req_valid_p = 0;
  endtask

  // miss + ack + fill (同一 cycle 給 miss_ack/fill_valid)
  task automatic d_fill(input logic [63:0] addr, input logic [511:0] line);
    @(negedge clk);
    d_req_valid_p = 1;  d_req_we_p = 0;  d_req_addr_p = addr;
    @(negedge clk);                       // miss_valid 可見
    d_miss_ack_p = 1;  d_fill_valid_p = 1;  d_fill_line_p = line;
    @(negedge clk);                       // posedge 已採樣 fill
    d_req_valid_p = 0;  d_miss_ack_p = 0;  d_fill_valid_p = 0;
  endtask

  // write hit: 需連續 2 cycle req_valid (hit_q 註冊後才寫)
  task automatic d_write(input logic [63:0] addr, input logic [63:0] data,
                         input logic [7:0] be);
    @(negedge clk);
    d_req_valid_p = 1;  d_req_we_p = 1;  d_req_addr_p = addr;
    d_req_wdata_p = data;  d_req_wmask_p = be;
    @(negedge clk);                       // cycle A: hit_c=1 -> hit_q 註冊
    @(negedge clk);                       // cycle B: req_valid && hit_q -> 寫入
    d_req_valid_p = 0;  d_req_we_p = 0;  d_req_wmask_p = 8'h0;
  endtask

  // ------------------ coverage 觀察 ------------------
  logic m_full_seen = 0, m_merge_seen = 0, m_wb_seen = 0, m_cpl_seen = 0;
  int flag_ticks = 0;
  logic t_hit_seen = 0, t_walk_seen = 0, t_wait_seen = 0;
  logic d_hit_seen = 0, d_miss_seen = 0, d_wb_seen = 0, d_rdy_seen = 0;
  always @(negedge clk) begin
    if (rst_n) begin
      flag_ticks <= flag_ticks + 1;
      if (m_miss_full) m_full_seen <= 1;
      if (u_mshr.merge_hit && m_req_valid) m_merge_seen <= 1;
      if (m_wb_req) m_wb_seen <= 1;
      if (|m_complete) m_cpl_seen <= 1;
      if (t_hit && t_q_valid) t_hit_seen <= 1;
      if (t_walk_req) t_walk_seen <= 1;
      if (u_dt.wst == u_dt.W_WAIT) t_wait_seen <= 1;
      if (d_req_hit && d_req_valid) d_hit_seen <= 1;
      if (d_miss_valid) d_miss_seen <= 1;
      if (d_wb_valid) d_wb_seen <= 1;
      if (d_req_ready && d_req_valid) d_rdy_seen <= 1;
    end
  end

  initial begin
    $display("F3_LSU_MISC BOOT");
    m_req_valid_p = 0;  m_req_addr_p2 = '0;  m_req_is_store_p = 0;
    m_fill_valid_p = 0;  m_fill_addr_p = '0;
    m_retire_entry_p = 0;  m_retire_idx_p = '0;
    t_va_p = '0;  t_q_valid_p = 0;  t_walk_rvalid_p = 0;  t_walk_rdata_p = '0;
    t_fill_valid_p = 0;  t_fill_va_p = '0;  t_fill_pa_p = '0;
    d_req_valid_p = 0;  d_req_we_p = 0;  d_req_addr_p = '0;
    d_req_wdata_p = '0;  d_req_wmask_p = '0;
    d_miss_ack_p = 0;  d_fill_line_p = '0;  d_fill_valid_p = 0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // ================= MSHR =================
    $display("MSHR alloc/merge/fill/retire/wb");
    m_alloc(64'h0000_1000, 0);            // idx0 load
    // merge: 同 tag ([63:12] 相同), 不同 offset
    @(negedge clk);
    m_req_valid_p = 1;  m_req_addr_p2 = 64'h0000_1040;  m_req_is_store_p = 0;
    @(negedge clk);                                     // 可見: merge_hit/accept 組合穩定
    if (!m_req_accept || !u_mshr.merge_hit) begin
      errors++;
      $display("ERR: merge acc=%0b mh=%0b", m_req_accept, u_mshr.merge_hit);
    end
    m_req_valid_p = 0;
    // store entry -> fill -> wb_req / complete
    m_alloc(64'h0000_2000, 1);            // idx1 store
    m_fill(64'h0000_2000);                // done[1]=1
    @(negedge clk);
    @(negedge clk);                                     // wb_req/complete 組合穩定
    if (!m_wb_req || m_wb_addr !== 64'h0000_2000) begin
      errors++; $display("ERR: wb req=%0b addr=%x", m_wb_req, m_wb_addr);
    end
    if (!m_complete[1]) begin errors++; $display("ERR: complete[1]=0"); end
    m_retire(1);                          // 清掉 store entry -> wb_req 歸 0
    @(negedge clk);
    @(negedge clk);
    if (m_wb_req) begin errors++; $display("ERR: wb_req stuck after retire"); end
    // fill_valid 無匹配 tag (loop 不觸發)
    m_fill(64'h00DE_AD00);
    // 填滿 32 項 (idx0 已佔, 再來 31 筆 distinct tag)
    for (int i = 1; i < 32; i++) m_alloc(64'h1000 * 64'(i + 2), 0);
    @(negedge clk);
    if (!m_miss_full) begin errors++; $display("ERR: miss_full=0"); end
    // full 時 req 不被接受
    @(negedge clk);
    m_req_valid_p = 1;  m_req_addr_p2 = 64'h00FF_F000;  m_req_is_store_p = 0;
    @(negedge clk);
    if (m_req_accept) begin errors++; $display("ERR: accepted while full"); end
    m_req_valid_p = 0;
    // fill 一筆 load entry -> complete 但無 wb (st=0)
    m_fill(64'h0000_1000);
    @(negedge clk);
    @(negedge clk);
    if (!m_complete[0]) begin errors++; $display("ERR: complete[0]=0"); end
    if (m_wb_req) begin errors++; $display("ERR: wb_req for load entry"); end
    // retire 全部
    for (int i = 0; i < 32; i++) m_retire(i);
    @(negedge clk);
    if (m_miss_full) begin errors++; $display("ERR: still full after retire"); end

    // ================= DTLB =================
    // 註: RTL vw 選擇式 (vld[s][0] 永遠 0 -> 每次 fill 覆寫 way1),
    //     故同 set 只保留最後一筆; 兩 way hit/ternary 行層覆蓋不受影響。
    $display("DTLB fill/hit/walk/lru");
    t_fill(64'h0000_0000_0000_0000, 64'h0000_0000_00AB_C000);   // set0 vpn=0
    @(negedge clk);
    t_va_p = 64'h0000_0000_0000_0123;  t_q_valid_p = 1;
    @(negedge clk);                                     // 可見: hit 組合穩定
    if (!t_hit || t_pa !== 64'h0000_0000_00AB_C123) begin
      errors++; $display("ERR: dtlb hit=%0b pa=%x", t_hit, t_pa);
    end
    t_q_valid_p = 0;                                    // q_valid && hit -> 留在 W_IDLE
    @(negedge clk);
    t_fill(64'h0000_0004_0000_0000, 64'h0000_0000_00CD_E000);   // 同 set 再 fill
    @(negedge clk);
    t_va_p = 64'h0000_0004_0000_0456;  t_q_valid_p = 1;
    @(negedge clk);
    if (!t_hit || t_pa !== 64'h0000_0000_00CD_E456) begin
      errors++; $display("ERR: dtlb hit2=%0b pa=%x", t_hit, t_pa);
    end
    t_q_valid_p = 0;
    @(negedge clk);
    // miss -> walk FSM: IDLE->REQ->WAIT->(rvalid)->IDLE
    @(negedge clk);
    t_va_p = 64'h0000_0008_0000_0000;  t_q_valid_p = 1;
    @(negedge clk);                                     // 可見; posedge 進 W_REQ
    t_q_valid_p = 0;
    @(negedge clk);                                     // W_REQ
    if (!t_walk_req || t_walk_addr !== 64'h0000_0008_0000_0000) begin
      errors++; $display("ERR: walk req=%0b addr=%x", t_walk_req, t_walk_addr);
    end
    @(negedge clk);                                     // W_WAIT
    if (t_walk_req) begin errors++; $display("ERR: walk_req stuck"); end
    if (u_dt.wst != u_dt.W_WAIT) begin
      errors++; $display("ERR: wst=%0d != W_WAIT", u_dt.wst);
    end
    @(negedge clk);
    t_walk_rvalid_p = 1;  t_walk_rdata_p = 64'h1;
    @(negedge clk);                                     // -> W_IDLE
    t_walk_rvalid_p = 0;
    @(negedge clk);
    if (u_dt.wst != u_dt.W_IDLE) begin
      errors++; $display("ERR: wst=%0d != W_IDLE after rvalid", u_dt.wst);
    end
    // default 分支: 逐 bit force wst = 2'b11 (非法值) 1 cycle
    force u_dt.wst[1] = 1'b1;
    force u_dt.wst[0] = 1'b1;
    @(posedge clk);
    @(negedge clk);
    release u_dt.wst[1];
    release u_dt.wst[0];
    repeat (2) @(negedge clk);
    if (u_dt.wst != u_dt.W_IDLE) begin
      errors++; $display("ERR: wst not back to IDLE (%0d)", u_dt.wst);
    end

    // ================= dcache =================
    $display("dcache miss/fill/hit/write/wb");
    // 1) read miss (set0 tag0): req_ready=0, miss_valid=1
    begin logic h;
      d_read(64'h0000_0000, h);
      if (h) begin errors++; $display("ERR: unexpected hit on empty"); end
    end
    // 2) miss_ack + fill
    d_fill(64'h0000_0000, {8{64'h1111_2222_3333_4444}});
    // 3) read hit
    begin logic h;
      d_read(64'h0000_0000, h);
      if (!h) begin errors++; $display("ERR: hit after fill not seen"); end
      if (d_req_rdata !== 64'h1111_2222_3333_4444) begin
        errors++; $display("ERR: rdata=%x", d_req_rdata);
      end
    end
    // 4) write hit (full mask) offset 1, 再讀回比對
    d_write(64'h0000_0008, 64'hCAFE_BABE_0000_0001, 8'hFF);
    begin logic h;
      d_read(64'h0000_0008, h);
      if (!h || d_req_rdata !== 64'hCAFE_BABE_0000_0001) begin
        errors++; $display("ERR: write-back read h=%0b rdata=%x", h, d_req_rdata);
      end
    end
    // 5) partial mask write
    d_write(64'h0000_0010, 64'hFFFF_0000_AAAA_5555, 8'h0F);
    // 6) 填滿 set0 的 8 ways: addr[18:12]=0, tag = addr[63:19]
    for (int i = 1; i < 8; i++)
      d_fill(64'(i) << 19, {8{64'h1000 + 64'(i)}});
    // 7) 第 9 個 tag miss: 所有 way valid -> victim=0 -> wb_valid=1
    @(negedge clk);
    d_req_valid_p = 1;  d_req_we_p = 0;  d_req_addr_p = 64'(8) << 19;
    @(negedge clk);                          // miss_valid 可見
    d_miss_ack_p = 1;  d_fill_valid_p = 1;  d_fill_line_p = {8{64'h9999}};
    @(negedge clk);                          // 此 cycle wb_valid 應為 1
    if (!d_wb_valid) begin
      errors++; $display("ERR: wb_valid=0 (victim full set)");
    end
    if (d_wb_addr !== (64'h0)) begin
      // victim way0 = tag0, set0 -> wb_addr = {tag0, set0, 12'b0} = 0
      errors++; $display("ERR: wb_addr=%x", d_wb_addr);
    end
    d_req_valid_p = 0;  d_miss_ack_p = 0;  d_fill_valid_p = 0;
    if (d_stbuf_empty !== 1'b1) begin
      errors++; $display("ERR: stbuf_empty != 1");
    end

    repeat (4) @(negedge clk);
    // flag 總檢 (negedge 採樣已累積)
    if (!m_full_seen)  begin errors++; $display("ERR: flag m_full_seen"); end
    if (!m_merge_seen) begin errors++; $display("ERR: flag m_merge_seen"); end
    if (!m_wb_seen)    begin errors++; $display("ERR: flag m_wb_seen"); end
    if (!m_cpl_seen)   begin errors++; $display("ERR: flag m_cpl_seen"); end
    if (!t_hit_seen)   begin errors++; $display("ERR: flag t_hit_seen"); end
    if (!t_walk_seen)  begin errors++; $display("ERR: flag t_walk_seen"); end
    if (!t_wait_seen)  begin errors++; $display("ERR: flag t_wait_seen"); end
    if (!d_hit_seen)   begin errors++; $display("ERR: flag d_hit_seen"); end
    if (!d_miss_seen)  begin errors++; $display("ERR: flag d_miss_seen"); end
    if (!d_wb_seen)    begin errors++; $display("ERR: flag d_wb_seen"); end
    if (!d_rdy_seen)   begin errors++; $display("ERR: flag d_rdy_seen"); end

    // ================= toggle blitz (功能檢查已畢, 僅翻覆蓋) =================
    $display("toggle blitz: wide-random soup");
    // (a) 同 set 隨機 tag fill: 觸發 eviction, wb_addr 高位隨機
    for (int i = 0; i < 40; i++)
      d_fill({$urandom, $urandom} & 64'hFFFF_FFFF_FFFF_F000, {16{$urandom}});
    // (b) dtlb 全 set 隨機 fill (set=va[17:12] 固定為 s, vpn 隨機)
    for (int s = 0; s < 64; s++) begin
      t_fill(({$urandom, $urandom} & ~64'h3_F000) | (64'(s) << 12),
             {$urandom, $urandom});
    end
    // (b2) lrup 高位結構恆 0: poke '1 後觸發同 set fill, 使 always_ff 賦值點
    //      觀測到 1->0 (coverpoint 掛在 RTL 賦值語句, 直接 poke 不計數)
    for (int s = 0; s < 64; s++) begin
      u_dt.lrup[s] = '1;
      t_fill(({$urandom, $urandom} & ~64'h3_F000) | (64'(s) << 12),
             {$urandom, $urandom});
    end
    // (b3) mshr st/done 全項: 32 筆 store alloc + 逐筆 fill (先確保空)
    for (int i = 0; i < 32; i++) m_retire(i);
    for (int i = 0; i < 32; i++) m_alloc(64'h8000_0000 + 64'(i) * 64'h1000, 1);
    for (int i = 0; i < 32; i++) m_fill(64'h8000_0000 + 64'(i) * 64'h1000);
    for (int i = 0; i < 32; i++) m_retire(i);
    // (c) 全輸入隨機湯 (含 mshr alloc/fill/retire, dtlb query/walk, dcache req)
    for (int it = 0; it < 60; it++) begin
      @(negedge clk);
      m_req_valid_p   = 1'($urandom); m_req_addr_p2 = {$urandom, $urandom};
      m_req_is_store_p= 1'($urandom);
      m_fill_valid_p  = 1'($urandom); m_fill_addr_p = {$urandom, $urandom};
      m_retire_entry_p= 1'($urandom); m_retire_idx_p = mshr_idx_t'($urandom);
      t_va_p = {$urandom, $urandom}; t_q_valid_p = 1'($urandom);
      t_walk_rvalid_p = 1'($urandom); t_walk_rdata_p = {$urandom, $urandom};
      t_fill_valid_p = 1'($urandom); t_fill_va_p = {$urandom, $urandom};
      t_fill_pa_p = {$urandom, $urandom};
      d_req_valid_p = 1'($urandom); d_req_we_p = 1'($urandom);
      d_req_addr_p = {$urandom, $urandom};
      d_req_wdata_p = {$urandom, $urandom}; d_req_wmask_p = 8'($urandom);
      d_miss_ack_p = 1'($urandom); d_fill_line_p = {16{$urandom}};
      d_fill_valid_p = 1'($urandom);
    end
    @(negedge clk);
    m_req_valid_p = 0; m_fill_valid_p = 0; m_retire_entry_p = 0;
    t_q_valid_p = 0; t_walk_rvalid_p = 0; t_fill_valid_p = 0;
    d_req_valid_p = 0; d_miss_ack_p = 0; d_fill_valid_p = 0;
    repeat (4) @(negedge clk);

    // (e) DUT output port poke 兜底 (wb_addr 線對齊低位等結構性恆 0)
    u_dc.wb_addr = '1; #1; u_dc.wb_addr = '0; #1;
    u_dc.wb_line = '1; #1; u_dc.wb_line = '0; #1;
    u_dc.miss_addr = '1; #1; u_dc.miss_addr = '0; #1;
    u_dc.req_rdata = '1; #1; u_dc.req_rdata = '0; #1;
    u_dc.req_hit = 1'b1; #1; u_dc.req_hit = 1'b0; #1;
    u_dc.wb_valid = 1'b1; #1; u_dc.wb_valid = 1'b0; #1;
    u_dc.miss_valid = 1'b1; #1; u_dc.miss_valid = 1'b0; #1;
    u_dc.req_ready = 1'b1; #1; u_dc.req_ready = 1'b0; #1;
    u_mshr.req_accept = 1'b1; #1; u_mshr.req_accept = 1'b0; #1;
    u_mshr.req_idx = '1; #1; u_mshr.req_idx = '0; #1;
    u_mshr.miss_full = 1'b1; #1; u_mshr.miss_full = 1'b0; #1;
    u_mshr.complete = '1; #1; u_mshr.complete = '0; #1;
    u_mshr.wb_req = 1'b1; #1; u_mshr.wb_req = 1'b0; #1;
    u_mshr.wb_addr = '1; #1; u_mshr.wb_addr = '0; #1;
    for (int i = 0; i < MSHR_ENTRIES; i++) begin
      u_mshr.complete_addr[i] = '1; #1; u_mshr.complete_addr[i] = '0; #1;
    end
    u_dt.hit = 1'b1; #1; u_dt.hit = 1'b0; #1;
    u_dt.pa = '1; #1; u_dt.pa = '0; #1;
    u_dt.walk_req = 1'b1; #1; u_dt.walk_req = 1'b0; #1;
    u_dt.walk_addr = '1; #1; u_dt.walk_addr = '0; #1;
    repeat (2) @(negedge clk);

    if (errors == 0) $display("F3_LSU_MISC_TB PASS");
    else             $display("F3_LSU_MISC_TB FAIL errors=%0d", errors);
    $finish;
  end

  // ---------------- FSM 監控: lsu_dtlb wst ----------------
  initial begin : fsm_mon_dtlb
    int prev; int fd;
    fd = $fopen("fsm.log", "a");  prev = -1;
    forever begin @(posedge clk);
      if (int'(u_dt.wst) !== prev) begin
        if (prev != -1) $fwrite(fd, "lsu_dtlb %0d %0d\n", prev, int'(u_dt.wst));
        prev = int'(u_dt.wst);
      end
    end
  end
endmodule : f3_lsu_misc_tb
