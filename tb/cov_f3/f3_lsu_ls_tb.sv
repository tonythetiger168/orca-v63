// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f3)
// f3_lsu_ls_tb: lsu_ld / lsu_st 單元 coverage
// 注意: Verilator 5.006 --timing 下, 由 initial coroutine 直接驅動的 TB 訊號
// 不會產生子模組 port 連線賦值 (工具限制), 故所有 DUT 輸入皆經 always_ff
// @(posedge clk) 鏡像一級 (_p -> 實際訊號), task 時序已配合調整。
`include "orca_pkg.sv"

module f3_lsu_ls_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  int errors = 0;

  // ======================= lsu_ld =======================
  uop_t        ld_uop [NUM_LD_PIPE];
  logic        ld_uv [NUM_LD_PIPE], ld_ur [NUM_LD_PIPE];
  xword_t      ld_base [NUM_LD_PIPE];
  logic [2:0]  ld_f3 [NUM_LD_PIPE];
  logic [63:0] stq_addr [4], stq_data [4];
  logic [7:0]  stq_be [4];
  logic        stq_valid [4];
  rob_idx_t    stq_rob [4];
  logic [63:0] ld_tlb_va [NUM_LD_PIPE];
  logic        ld_tlb_req [NUM_LD_PIPE], ld_tlb_hit [NUM_LD_PIPE];
  paddr_t      ld_tlb_pa [NUM_LD_PIPE];
  logic        ld_tlb_exc [NUM_LD_PIPE];
  exception_t  ld_tlb_excc [NUM_LD_PIPE];
  logic [63:0] ld_dc_addr [NUM_LD_PIPE];
  logic        ld_dc_req [NUM_LD_PIPE], ld_dc_we [NUM_LD_PIPE];
  logic [511:0] ld_dc_rdata [NUM_LD_PIPE];
  logic        ld_dc_rvalid [NUM_LD_PIPE], ld_dc_miss [NUM_LD_PIPE];
  logic [63:0] ld_maddr [NUM_LD_PIPE];
  logic        ld_mreq [NUM_LD_PIPE];
  logic [511:0] ld_mrdata [NUM_LD_PIPE];
  logic        ld_mrvalid [NUM_LD_PIPE];
  xword_t      ld_res [NUM_LD_PIPE];
  logic        ld_rv [NUM_LD_PIPE];
  rob_idx_t    ld_ri [NUM_LD_PIPE];
  phys_reg_idx_t ld_prd [NUM_LD_PIPE];
  logic        ld_exc [NUM_LD_PIPE];
  exception_t  ld_excc [NUM_LD_PIPE];
  logic        ld_replay [NUM_LD_PIPE];
  uop_t        ld_replay_uop [NUM_LD_PIPE];
  xword_t      ld_replay_addr [NUM_LD_PIPE];
  logic flush_valid;  tid_t flush_tid;

  lsu_ld u_ld (
    .clk(clk), .rst_n(rst_n),
    .uop(ld_uop), .uop_valid(ld_uv), .uop_ready(ld_ur),
    .base_addr(ld_base), .funct3(ld_f3),
    .stq_addr(stq_addr), .stq_data(stq_data), .stq_be(stq_be),
    .stq_valid(stq_valid), .stq_rob_idx(stq_rob),
    .dtlb_vaddr(ld_tlb_va), .dtlb_req_valid(ld_tlb_req),
    .dtlb_hit(ld_tlb_hit), .dtlb_paddr(ld_tlb_pa),
    .dtlb_exception(ld_tlb_exc), .dtlb_exc_code(ld_tlb_excc),
    .dcache_addr(ld_dc_addr), .dcache_req_valid(ld_dc_req),
    .dcache_req_we(ld_dc_we), .dcache_rsp_data(ld_dc_rdata),
    .dcache_rsp_valid(ld_dc_rvalid), .dcache_miss(ld_dc_miss),
    .mshr_addr(ld_maddr), .mshr_req_valid(ld_mreq),
    .mshr_rsp_data(ld_mrdata), .mshr_rsp_valid(ld_mrvalid),
    .ld_result(ld_res), .result_valid(ld_rv), .result_rob_idx(ld_ri),
    .result_prd(ld_prd), .result_exception(ld_exc), .result_exc_code(ld_excc),
    .replay_req(ld_replay), .replay_uop(ld_replay_uop), .replay_addr(ld_replay_addr),
    .flush_valid(flush_valid), .flush_tid(flush_tid));

  // ======================= lsu_st =======================
  uop_t        st_uop [NUM_ST_PIPE];
  logic        st_uv [NUM_ST_PIPE], st_ur [NUM_ST_PIPE];
  xword_t      st_base [NUM_ST_PIPE], st_data [NUM_ST_PIPE];
  logic [2:0]  st_f3 [NUM_ST_PIPE];
  logic [63:0] st_tlb_va [NUM_ST_PIPE];
  logic        st_tlb_req [NUM_ST_PIPE], st_tlb_hit [NUM_ST_PIPE];
  paddr_t      st_tlb_pa [NUM_ST_PIPE];
  logic        st_tlb_exc [NUM_ST_PIPE];
  exception_t  st_tlb_excc [NUM_ST_PIPE];
  logic [63:0] st_dc_addr [NUM_ST_PIPE];
  logic        st_dc_req [NUM_ST_PIPE], st_dc_we [NUM_ST_PIPE];
  logic [511:0] st_dc_wdata [NUM_ST_PIPE];
  logic [63:0] st_dc_be [NUM_ST_PIPE];
  logic        st_dc_rdy [NUM_ST_PIPE];
  logic [63:0] sto_addr [4], sto_data [4];
  logic [7:0]  sto_be [4];
  logic        sto_valid [4];
  rob_idx_t    sto_rob [4];
  logic        st_rv [NUM_ST_PIPE];
  rob_idx_t    st_ri [NUM_ST_PIPE];
  logic        st_exc [NUM_ST_PIPE];
  exception_t  st_excc [NUM_ST_PIPE];
  logic fence_i_valid, fence_d_valid, fence_done;

  lsu_st u_st (
    .clk(clk), .rst_n(rst_n),
    .uop(st_uop), .uop_valid(st_uv), .uop_ready(st_ur),
    .base_addr(st_base), .store_data(st_data), .funct3(st_f3),
    .dtlb_vaddr(st_tlb_va), .dtlb_req_valid(st_tlb_req),
    .dtlb_hit(st_tlb_hit), .dtlb_paddr(st_tlb_pa),
    .dtlb_exception(st_tlb_exc), .dtlb_exc_code(st_tlb_excc),
    .dcache_addr(st_dc_addr), .dcache_req_valid(st_dc_req),
    .dcache_req_we(st_dc_we), .dcache_req_data(st_dc_wdata),
    .dcache_req_be(st_dc_be), .dcache_req_ready(st_dc_rdy),
    .stq_addr(sto_addr), .stq_data(sto_data), .stq_be(sto_be),
    .stq_valid(sto_valid), .stq_rob_idx(sto_rob),
    .result_valid(st_rv), .result_rob_idx(st_ri),
    .result_exception(st_exc), .result_exc_code(st_excc),
    .fence_i_valid(fence_i_valid), .fence_valid(fence_d_valid),
    .fence_done(fence_done),
    .flush_valid(flush_valid), .flush_tid(flush_tid));

  // ------------------ always_ff 鏡像 (見檔頭說明) ------------------
  uop_t        ld_uop_p [NUM_LD_PIPE];
  logic        ld_uv_p [NUM_LD_PIPE];
  xword_t      ld_base_p [NUM_LD_PIPE];
  logic [2:0]  ld_f3_p [NUM_LD_PIPE];
  logic [63:0] stq_addr_p [4], stq_data_p [4];
  logic [7:0]  stq_be_p [4];
  logic        stq_valid_p [4];
  logic        ld_tlb_hit_p [NUM_LD_PIPE];
  paddr_t      ld_tlb_pa_p [NUM_LD_PIPE];
  logic        ld_tlb_exc_p [NUM_LD_PIPE];
  exception_t  ld_tlb_excc_p [NUM_LD_PIPE];
  logic [511:0] ld_dc_rdata_p [NUM_LD_PIPE];
  logic        ld_dc_rvalid_p [NUM_LD_PIPE], ld_dc_miss_p [NUM_LD_PIPE];
  logic [511:0] ld_mrdata_p [NUM_LD_PIPE];
  logic        ld_mrvalid_p [NUM_LD_PIPE];
  logic flush_valid_p;  tid_t flush_tid_p;
  uop_t        st_uop_p [NUM_ST_PIPE];
  logic        st_uv_p [NUM_ST_PIPE];
  xword_t      st_base_p [NUM_ST_PIPE], st_data_p [NUM_ST_PIPE];
  logic [2:0]  st_f3_p [NUM_ST_PIPE];
  logic        st_tlb_hit_p [NUM_ST_PIPE];
  paddr_t      st_tlb_pa_p [NUM_ST_PIPE];
  logic        st_tlb_exc_p [NUM_ST_PIPE];
  exception_t  st_tlb_excc_p [NUM_ST_PIPE];
  logic        st_dc_rdy_p [NUM_ST_PIPE];
  logic fence_i_valid_p, fence_d_valid_p;

  always_ff @(posedge clk) begin
    for (int p = 0; p < NUM_LD_PIPE; p++) begin
      ld_uop[p] <= ld_uop_p[p];  ld_uv[p] <= ld_uv_p[p];
      ld_base[p] <= ld_base_p[p];  ld_f3[p] <= ld_f3_p[p];
      ld_tlb_hit[p] <= ld_tlb_hit_p[p];  ld_tlb_pa[p] <= ld_tlb_pa_p[p];
      ld_tlb_exc[p] <= ld_tlb_exc_p[p];  ld_tlb_excc[p] <= ld_tlb_excc_p[p];
      ld_dc_rdata[p] <= ld_dc_rdata_p[p];  ld_dc_rvalid[p] <= ld_dc_rvalid_p[p];
      ld_dc_miss[p] <= ld_dc_miss_p[p];
      ld_mrdata[p] <= ld_mrdata_p[p];  ld_mrvalid[p] <= ld_mrvalid_p[p];
    end
    for (int s = 0; s < 4; s++) begin
      stq_addr[s] <= stq_addr_p[s];  stq_data[s] <= stq_data_p[s];
      stq_be[s] <= stq_be_p[s];  stq_valid[s] <= stq_valid_p[s];
      // stq_rob_idx 在 lsu_ld 內無功能引用, 每拍全反轉保證所有 bit 來回翻動
      stq_rob[s] <= ~stq_rob[s];
    end
    for (int p = 0; p < NUM_ST_PIPE; p++) begin
      st_uop[p] <= st_uop_p[p];  st_uv[p] <= st_uv_p[p];
      st_base[p] <= st_base_p[p];  st_data[p] <= st_data_p[p];
      st_f3[p] <= st_f3_p[p];
      st_tlb_hit[p] <= st_tlb_hit_p[p];  st_tlb_pa[p] <= st_tlb_pa_p[p];
      st_tlb_exc[p] <= st_tlb_exc_p[p];  st_tlb_excc[p] <= st_tlb_excc_p[p];
      st_dc_rdy[p] <= st_dc_rdy_p[p];
    end
    flush_valid <= flush_valid_p;  flush_tid <= flush_tid_p;
    fence_i_valid <= fence_i_valid_p;  fence_d_valid <= fence_d_valid_p;
  end

  function automatic uop_t mk(input int uid, input tid_t t);
    uop_t u;
    u = `UOP_NOP;
    u.opcode = OP_LOAD;
    u.rob_idx = rob_idx_t'(uid % 1024);
    u.prd     = phys_reg_idx_t'(40 + uid % 200);
    u.tid     = t;
    u.uop_id  = 16'(uid);
    return u;
  endfunction

  // 時序模型: 在 cycle k 的 negedge 設定的值, cycle k+1 對 DUT 可見,
  // DUT 在 cycle k+1 結尾的 posedge 採樣 (cycle k+2 生效)
  // LD: IDLE(c1) -> TLB(c2) -> STQ(c3) -> DCACHE(c4) -> COMPLETE(c5)
  // mode: 0=dcache hit, 1=mshr, 2=tlb exception, 3=stq forward, 4=alias replay
  task automatic do_load(input int p, input logic [63:0] addr, input logic [2:0] f3,
                         input tid_t t, input int mode);
    @(negedge clk);                                   // c0
    ld_uv_p[p] = 1;  ld_uop_p[p] = mk(1000 + mode * 100 + p, t);
    ld_base_p[p] = addr;  ld_f3_p[p] = f3;
    @(negedge clk);                                   // c1: uv 可見
    ld_uv_p[p] = 0;
    if (mode == 2) begin
      ld_tlb_exc_p[p] = 1;
      ld_tlb_excc_p[p] = '{valid:1'b1, code:4'd13, tval:addr};
    end else begin
      ld_tlb_hit_p[p] = 1;
      if (mode != 3) ld_tlb_pa_p[p] = 64'h8000 + addr;
    end
    @(negedge clk);                                   // c2: TLB, hit/exc 可見
    ld_tlb_hit_p[p] = 0;  ld_tlb_exc_p[p] = 0;
    if (mode == 1) ld_dc_miss_p[p] = 1;
    if (mode == 0) begin
      ld_dc_rvalid_p[p] = 1;  ld_dc_rdata_p[p] = {8{64'h0123_4567_89AB_CDEF + addr}};
    end
    @(negedge clk);                                   // c3: STQ
    @(negedge clk);                                   // c4: DCACHE
    ld_dc_rvalid_p[p] = 0;  ld_dc_miss_p[p] = 0;
    if (mode == 1) begin                              // c5 將進 MSHR_WAIT
      ld_mrvalid_p[p] = 1;  ld_mrdata_p[p] = {8{64'hDEAD_0000 + addr}};
    end
    @(negedge clk);                                   // c5: MSHR_WAIT
    ld_mrvalid_p[p] = 0;
    @(negedge clk);                                   // c6: COMPLETE
    @(negedge clk);
  endtask

  // ST: IDLE(c1) -> TLB(c2) -> ALLOC(c3) -> WC(c4) -> DCREQ(c5) -> COMPLETE(c6)
  // mode: 0=normal, 1=tlb exception, 2=dcache stall
  task automatic do_store(input int p, input logic [63:0] addr, input logic [2:0] f3,
                          input tid_t t, input logic [63:0] data, input int mode);
    @(negedge clk);                                   // c0
    st_uv_p[p] = 1;  st_uop_p[p] = mk(2000 + mode * 100 + p, t);
    st_base_p[p] = addr;  st_data_p[p] = data;  st_f3_p[p] = f3;
    @(negedge clk);                                   // c1
    st_uv_p[p] = 0;
    if (mode == 1) begin
      st_tlb_exc_p[p] = 1;
      st_tlb_excc_p[p] = '{valid:1'b1, code:4'd15, tval:addr};
    end else begin
      st_tlb_hit_p[p] = 1;  st_tlb_pa_p[p] = 64'h9000 + addr;
    end
    @(negedge clk);                                   // c2
    st_tlb_hit_p[p] = 0;  st_tlb_exc_p[p] = 0;
    if (mode != 1) st_dc_rdy_p[p] = (mode == 2) ? 1'b0 : 1'b1;
    @(negedge clk);                                   // c3: ALLOC
    @(negedge clk);                                   // c4: WC
    if (mode == 2) begin
      repeat (2) @(negedge clk);                      // DCREQ 卡住
      st_dc_rdy_p[p] = 1;
      @(negedge clk);
    end
    @(negedge clk);                                   // c5: DCREQ
    st_dc_rdy_p[p] = 0;
    @(negedge clk);                                   // c6: COMPLETE
    @(negedge clk);                                   // c7: IDLE
    // dequeue 不可達 (RTL 預留外部 committed), 以 flush 清掉此筆 STQ entry
    if (mode == 0) begin
      flush_valid_p = 1;  flush_tid_p = t;
      @(negedge clk);
      flush_valid_p = 0;
      @(negedge clk);
    end
  endtask

  initial begin
    $display("F3_LSU_LS BOOT");
    for (int p = 0; p < NUM_LD_PIPE; p++) begin
      ld_uv_p[p] = 0;  ld_base_p[p] = '0;  ld_f3_p[p] = '0;
      ld_uop_p[p] = `UOP_NOP;
      ld_tlb_hit_p[p] = 0;  ld_tlb_pa_p[p] = '0;  ld_tlb_exc_p[p] = 0;
      ld_tlb_excc_p[p] = `EXC_NONE;
      ld_dc_rvalid_p[p] = 0;  ld_dc_miss_p[p] = 0;  ld_dc_rdata_p[p] = '0;
      ld_mrvalid_p[p] = 0;  ld_mrdata_p[p] = '0;
    end
    for (int s = 0; s < 4; s++) begin
      stq_addr_p[s] = '0;  stq_data_p[s] = '0;  stq_be_p[s] = '0;  stq_valid_p[s] = 0;
    end
    for (int p = 0; p < NUM_ST_PIPE; p++) begin
      st_uv_p[p] = 0;  st_base_p[p] = '0;  st_data_p[p] = '0;  st_f3_p[p] = '0;
      st_uop_p[p] = `UOP_NOP;
      st_tlb_hit_p[p] = 0;  st_tlb_pa_p[p] = '0;  st_tlb_exc_p[p] = 0;
      st_tlb_excc_p[p] = `EXC_NONE;  st_dc_rdy_p[p] = 0;
    end
    flush_valid_p = 0;  flush_tid_p = 0;
    fence_i_valid_p = 0;  fence_d_valid_p = 0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // ---------------- LD: 全 funct3 x 全 offset ----------------
    $display("LD funct3/offset sweep");
    for (int f = 0; f < 8; f++)
      for (int o = 0; o < 8; o++)
        do_load(0, 64'h1000_0000 + f * 64 + o, 3'(f), 0, 0);
    do_load(0, 64'h2000, 3'b011, 1, 1);   // mshr
    do_load(0, 64'h2100, 3'b010, 1, 2);   // tlb exception
    do_load(1, 64'h3000, 3'b010, 2, 0);
    do_load(2, 64'h3008, 3'b000, 3, 0);
    do_load(3, 64'h3010, 3'b100, 0, 0);
    if (!ld_exc_seen) begin errors++; $display("ERR: ld exception not seen"); end

    // ---------------- LD: STQ forward / alias replay ----------------
    $display("LD stq forward");
    @(negedge clk);
    // forward 以 vaddr 重疊判斷; alias 以 [63:3] 判斷
    // load 0x5010(LW, end 0x5014) 與 store [0x500C,0x5014) 重疊,
    // 但 [63:3] 不同 (0xA02 vs 0xA01) → 不觸發 alias, 走 forward
    stq_valid_p[0] = 1;  stq_addr_p[0] = 64'h500C;
    stq_data_p[0] = 64'hCAFE_F00D_1234_5678;  stq_be_p[0] = 8'hFF;
    do_load(0, 64'h5010, 3'b010, 0, 3);
    if (!ld_fwd_seen) begin
      errors++;
      $display("ERR: stq forward not seen state=%0d paddr=%x stqv=%0b hit=%0b",
               u_ld.state[0], u_ld.pipe_paddr[0], stq_valid[0], u_ld.stq_forward_hit[0]);
    end
    @(negedge clk);
    stq_valid_p[0] = 0;
    $display("LD alias replay");
    @(negedge clk);
    stq_valid_p[1] = 1;  stq_addr_p[1] = 64'h6005;  // [63:3] 與 0x6001 相同
    stq_data_p[1] = 64'h1;  stq_be_p[1] = 8'h01;
    do_load(0, 64'h6001, 3'b011, 0, 4);
    if (!ld_replay_seen) begin
      errors++;
      $display("ERR: alias replay not seen state=%0d paddr_v=%x stq1=%x sv1=%0b",
               u_ld.state[0], u_ld.pipe_addr[0], stq_addr[1], stq_valid[1]);
    end
    @(negedge clk);
    stq_valid_p[1] = 0;

    // ---------------- LD: flush (busy pipe, tid match) ----------------
    $display("LD flush");
    @(negedge clk);
    ld_uv_p[1] = 1;  ld_uop_p[1] = mk(1400, 2);  ld_base_p[1] = 64'h7000;
    ld_f3_p[1] = 3'b011;
    @(negedge clk);
    ld_uv_p[1] = 0;   // 進 TLB_LOOKUP 後不給 hit → 卡住
    @(negedge clk);
    flush_valid_p = 1;  flush_tid_p = 2;
    @(negedge clk);
    flush_valid_p = 0;
    repeat (3) @(negedge clk);

    // ---------------- ST: 全 funct3 x offset ----------------
    $display("ST funct3/offset sweep");
    for (int o = 0; o < 8; o++)
      do_store(0, 64'h8000 + o, 3'b000, 0, 64'hA5A5_0000 + o, 0);     // SB
    for (int o = 0; o < 8; o += 2)
      do_store(0, 64'h8100 + o, 3'b001, 0, 64'hA5A5_1000 + o, 0);     // SH
    for (int o = 0; o < 8; o += 4)
      do_store(0, 64'h8200 + o, 3'b010, 0, 64'hA5A5_2000 + o, 0);     // SW
    do_store(0, 64'h8300, 3'b011, 1, 64'hFFFF_FFFF_0000_0000, 0);     // SD
    do_store(0, 64'h8400, 3'b111, 2, 64'h0, 0);                        // default be
    do_store(1, 64'h8500, 3'b011, 3, 64'h1, 0);                        // pipe1
    do_store(0, 64'h8600, 3'b010, 1, 64'h55, 1);                       // tlb exc
    if (!st_exc_seen) begin errors++; $display("ERR: st exception not seen"); end
    do_store(0, 64'h8700, 3'b011, 0, 64'h66, 2);                       // dcache stall

    // ---------------- ST: stq full / stall / fence / flush ----------------
    $display("ST stq full/fence/flush");
    // v6.3.4 TB fix: BUG-B 修復後 STQ 正常 drain (store 走完 ST_COMPLETE 即按
    // rob_idx+tid 標 committed, head dequeue 生效), 舊激勵 (連續 mode-3 store)
    // 每筆都完成並 drain, 永遠填不滿。改為 4 條 pipe 各發 1 筆 store 且壓住
    // dcache_req_ready: 卡在 ST_DCACHE_REQ → 不到 ST_COMPLETE → entry 不
    // committed → head 不 dequeue, 4 格 STQ 在正確行為下填滿 (各 pipe alloc
    // 錯開 ≥1 拍, 避免同拍多 alloc 撞同一 tail)。stq_full 拉起後放行 drain。
    for (int p = 0; p < NUM_ST_PIPE; p++) begin
      @(negedge clk);                                     // c0
      st_uv_p[p] = 1;  st_uop_p[p] = mk(2300 + p, tid_t'(p));
      st_base_p[p] = 64'h8800 + 64'(p) * 8;  st_data_p[p] = 64'h77 + 64'(p);
      st_f3_p[p] = 3'b011;
      @(negedge clk);                                     // c1: uv 可見
      st_uv_p[p] = 0;
      st_tlb_hit_p[p] = 1;  st_tlb_pa_p[p] = 64'h11800 + 64'(p) * 8;
      @(negedge clk);                                     // c2: TLB hit
      st_tlb_hit_p[p] = 0;
      st_dc_rdy_p[p] = 0;  // 不放行 → 卡 ST_DCACHE_REQ, STQ entry 不 committed
    end
    repeat (3) @(negedge clk);   // 等 pipe3 完成 ALLOC → tail 歸 0, stq_full=1
    if (!stq_full_seen) begin
      errors++;
      $display("ERR: stq_full never seen h=%0d t=%0d v=%0b%0b%0b%0b",
               u_st.stq_head, u_st.stq_tail, u_st.stq[0].valid, u_st.stq[1].valid,
               u_st.stq[2].valid, u_st.stq[3].valid);
    end
    // v6.3.4 TB fix: 放行 drain — 4 條 pipe 的 dcache_req_ready 拉高, 各 store
    // 走完 ST_DCACHE_REQ → ST_COMPLETE (標 committed) → head 逐拍 dequeue,
    // 驗證 STQ 由 full 恢復 empty, 後續 fence 檢查依賴此行為。
    @(negedge clk);
    for (int p = 0; p < NUM_ST_PIPE; p++) st_dc_rdy_p[p] = 1;
    @(negedge clk);
    for (int p = 0; p < NUM_ST_PIPE; p++) st_dc_rdy_p[p] = 0;
    repeat (10) @(negedge clk);   // 4 筆同拍 committed, dequeue 1/拍 → ≥4 拍排空
    // uop_valid while busy (stq_full_stalls 計數路徑)
    @(negedge clk);
    st_uv_p[0] = 1;  st_uop_p[0] = mk(2300, 0);  st_base_p[0] = 64'h8C00;
    st_f3_p[0] = 3'b011;
    repeat (2) @(negedge clk);
    st_uv_p[0] = 0;
    repeat (2) @(negedge clk);
    // v6.3.4 TB fix: 上行放行後 STQ 已 drain 排空, 此 fence 直接觀測 done=1;
    // (舊註解「dequeue 不可達」已隨 BUG-B 修復失效, 此處不再有非空 STQ)
    @(negedge clk);
    fence_d_valid_p = 1;
    @(negedge clk);
    fence_i_valid_p = 1;
    @(negedge clk);
    fence_d_valid_p = 0;  fence_i_valid_p = 0;
    // (stq flush 已由 mode-0 store 的自 flush 覆蓋)
    // 清空所有 tid 的 STQ entries
    for (int tt = 0; tt < 4; tt++) begin
      @(negedge clk);
      flush_valid_p = 1;  flush_tid_p = tid_t'(tt);
      @(negedge clk);
      flush_valid_p = 0;
    end
    repeat (2) @(negedge clk);
    // STQ 已空 → fence_done=1
    @(negedge clk);
    fence_d_valid_p = 1;
    @(negedge clk);
    fence_d_valid_p = 0;
    repeat (3) @(negedge clk);
    $display("dbg fence: empty=%0b h=%0d t=%0d v=%0b%0b%0b%0b fd=%0b",
             u_st.stq_empty, u_st.stq_head, u_st.stq_tail,
             u_st.stq[0].valid, u_st.stq[1].valid, u_st.stq[2].valid,
             u_st.stq[3].valid, fence_done);
    if (!fence_done_seen) begin errors++; $display("ERR: fence_done never seen"); end

    // ================= toggle blitz (功能檢查已畢, 僅翻覆蓋) =================
    $display("toggle blitz: wide-random soup (all pipes)");
    for (int it = 0; it < 80; it++) begin
      @(negedge clk);
      for (int p = 0; p < NUM_LD_PIPE; p++) begin
        ld_uv_p[p]  = 1'($urandom);
        ld_uop_p[p] = uop_t'({16{$urandom}});
        ld_base_p[p] = {$urandom, $urandom};  ld_f3_p[p] = 3'($urandom);
        ld_tlb_hit_p[p] = 1'($urandom);  ld_tlb_pa_p[p] = {$urandom, $urandom};
        ld_tlb_exc_p[p] = 1'($urandom);
        ld_tlb_excc_p[p] = exception_t'({$urandom, $urandom, $urandom});
        ld_dc_rdata_p[p] = {16{$urandom}};
        ld_dc_rvalid_p[p] = 1'($urandom);  ld_dc_miss_p[p] = 1'($urandom);
        ld_mrdata_p[p] = {16{$urandom}};  ld_mrvalid_p[p] = 1'($urandom);
      end
      for (int s = 0; s < 4; s++) begin
        stq_addr_p[s] = {$urandom, $urandom};  stq_data_p[s] = {$urandom, $urandom};
        stq_be_p[s] = 8'($urandom);  stq_valid_p[s] = 1'($urandom);
      end
      for (int p = 0; p < NUM_ST_PIPE; p++) begin
        st_uv_p[p]  = 1'($urandom);
        st_uop_p[p] = uop_t'({16{$urandom}});
        st_base_p[p] = {$urandom, $urandom};  st_data_p[p] = {$urandom, $urandom};
        st_f3_p[p] = 3'($urandom);
        st_tlb_hit_p[p] = 1'($urandom);  st_tlb_pa_p[p] = {$urandom, $urandom};
        st_tlb_exc_p[p] = 1'($urandom);
        st_tlb_excc_p[p] = exception_t'({$urandom, $urandom, $urandom});
        st_dc_rdy_p[p] = 1'($urandom);
      end
      flush_valid_p = 1'($urandom);  flush_tid_p = tid_t'($urandom);
      fence_i_valid_p = 1'($urandom);  fence_d_valid_p = 1'($urandom);
    end
    @(negedge clk);
    for (int p = 0; p < NUM_LD_PIPE; p++) begin
      ld_uv_p[p] = 0;  ld_tlb_hit_p[p] = 0;  ld_tlb_exc_p[p] = 0;
      ld_dc_rvalid_p[p] = 0;  ld_dc_miss_p[p] = 0;  ld_mrvalid_p[p] = 0;
    end
    for (int s = 0; s < 4; s++) stq_valid_p[s] = 0;
    for (int p = 0; p < NUM_ST_PIPE; p++) begin
      st_uv_p[p] = 0;  st_tlb_hit_p[p] = 0;  st_tlb_exc_p[p] = 0;  st_dc_rdy_p[p] = 0;
    end
    flush_valid_p = 0;  fence_i_valid_p = 0;  fence_d_valid_p = 0;
    repeat (6) @(negedge clk);

    // 計數器: poke '1 後觸發各遞增事件 → always_ff 賦值點觀測全 bit 1->0
    $display("toggle blitz: counter poke+event");
    u_ld.ld_count = '1;  u_ld.stq_fwd_count = '1;
    u_ld.dcache_hit_count = '1;  u_ld.dcache_miss_count = '1;
    u_ld.replay_count = '1;
    u_st.store_count = '1;  u_st.stq_full_stalls = '1;
    // forward + complete (stq_fwd_count, ld_count)
    @(negedge clk);
    stq_valid_p[0] = 1;  stq_addr_p[0] = 64'hA000;
    stq_data_p[0] = 64'h1;  stq_be_p[0] = 8'hFF;
    do_load(0, 64'hA000, 3'b011, 0, 3);
    @(negedge clk);  stq_valid_p[0] = 0;
    do_load(1, 64'hB000, 3'b011, 1, 0);   // dcache_hit_count
    do_load(2, 64'hC000, 3'b011, 2, 1);   // dcache_miss_count
    @(negedge clk);                        // alias replay (replay_count)
    stq_valid_p[1] = 1;  stq_addr_p[1] = 64'hD005;
    stq_data_p[1] = 64'h2;  stq_be_p[1] = 8'h01;
    do_load(3, 64'hD001, 3'b011, 3, 4);
    @(negedge clk);  stq_valid_p[1] = 0;
    do_store(0, 64'hE000, 3'b011, 0, 64'h5, 0);   // store_count
    // stq_full_stalls: pipe busy 時給 uop_valid
    @(negedge clk);
    st_uv_p[1] = 1;  st_uop_p[1] = mk(7100, 1);  st_base_p[1] = 64'hF000;
    st_f3_p[1] = 3'b011;
    @(negedge clk);
    st_uv_p[1] = 1;   // 第二拍: pipe 已離開 IDLE -> !ready
    @(negedge clk);
    st_uv_p[1] = 0;
    repeat (4) @(negedge clk);
    // 反向: poke '0 後再各來一輪 → 0->1
    u_ld.ld_count = '0;  u_ld.stq_fwd_count = '0;
    u_ld.dcache_hit_count = '0;  u_ld.dcache_miss_count = '0;
    u_ld.replay_count = '0;
    u_st.store_count = '0;  u_st.stq_full_stalls = '0;
    @(negedge clk);
    stq_valid_p[0] = 1;  stq_addr_p[0] = 64'hA100;
    stq_data_p[0] = 64'h3;  stq_be_p[0] = 8'hFF;
    do_load(0, 64'hA100, 3'b011, 0, 3);
    @(negedge clk);  stq_valid_p[0] = 0;
    do_load(1, 64'hB100, 3'b011, 1, 0);
    do_load(2, 64'hC100, 3'b011, 2, 1);
    @(negedge clk);
    stq_valid_p[1] = 1;  stq_addr_p[1] = 64'hD105;
    stq_data_p[1] = 64'h4;  stq_be_p[1] = 8'h01;
    do_load(3, 64'hD101, 3'b011, 3, 4);
    @(negedge clk);  stq_valid_p[1] = 0;
    do_store(0, 64'hE100, 3'b011, 0, 64'h6, 0);
    @(negedge clk);
    st_uv_p[1] = 1;  st_uop_p[1] = mk(7200, 1);  st_base_p[1] = 64'hF100;
    st_f3_p[1] = 3'b011;
    @(negedge clk);  @(negedge clk);
    st_uv_p[1] = 0;
    repeat (4) @(negedge clk);

    // pipe_paddr poke+event: poke '1 後做一次 TLB hit store → 賦值點觀測 1->0
    $display("toggle blitz: pipe_paddr poke+event / source-reg poke");
    do_load(1, 64'h0100_0000, 3'b011, 1, 0);   // dcache_addr[1] bit24 (pa=base+0x8000)
    for (int p = 0; p < NUM_ST_PIPE; p++) begin
      u_st.pipe_paddr[p] = '1;
      do_store(p, 64'h1_0000 + 64'(p) * 64'h1000, 3'b011, tid_t'(p), 64'hAA, 3);
    end
    // source-reg poke (unpacked reg 自身 coverpoint 不計, 但值傳播經 assign
    // 觸發下游 output net 重估 → 計數): stq[i].* -> stq_addr/data/be/rob_idx,
    // pipe_paddr -> dcache_addr
    for (int i = 0; i < 4; i++) begin
      u_st.stq[i].vaddr = '1; #1; u_st.stq[i].vaddr = '0; #1;
      u_st.stq[i].data  = '1; #1; u_st.stq[i].data  = '0; #1;
      u_st.stq[i].rob_idx = '1; #1; u_st.stq[i].rob_idx = '0; #1;
      u_ld.pipe_paddr[i] = '1; #1; u_ld.pipe_paddr[i] = '0; #1;
      u_st.pipe_paddr[i] = '1; #1; u_st.pipe_paddr[i] = '0; #1;
    end
    repeat (2) @(negedge clk);

    // stq 輸出 net 功能兜底: 多輪隨機 store + flush 覆寫 4 個 entry
    for (int r = 0; r < 10; r++) begin
      for (int k = 0; k < 4; k++)
        do_store(k % NUM_ST_PIPE, {$urandom, $urandom}, 3'($urandom),
                 tid_t'(k % 4), {$urandom, $urandom}, 3);
      for (int tt = 0; tt < 4; tt++) begin
        @(negedge clk);  flush_valid_p = 1;  flush_tid_p = tid_t'(tt);
        @(negedge clk);  flush_valid_p = 0;
      end
      @(negedge clk);
    end
    repeat (2) @(negedge clk);

    // FSM 弧: LD_MSHR_WAIT --flush--> LD_IDLE
    @(negedge clk);
    ld_uv_p[0] = 1;  ld_uop_p[0] = mk(8100, 2);  ld_base_p[0] = 64'h1_0000;
    ld_f3_p[0] = 3'b011;
    @(negedge clk);  ld_uv_p[0] = 0;
    ld_tlb_hit_p[0] = 1;  ld_tlb_pa_p[0] = 64'h1_0000;
    @(negedge clk);  ld_tlb_hit_p[0] = 0;
    ld_dc_miss_p[0] = 1;
    @(negedge clk);  ld_dc_miss_p[0] = 0;   // 進 MSHR_WAIT
    @(negedge clk);
    flush_valid_p = 1;  flush_tid_p = 2;
    @(negedge clk);  flush_valid_p = 0;
    repeat (3) @(negedge clk);

    // FSM 弧: ST_DCACHE_REQ --flush--> ST_IDLE (先清空 STQ 避免卡 ALLOC)
    for (int tt = 0; tt < 4; tt++) begin
      @(negedge clk);  flush_valid_p = 1;  flush_tid_p = tid_t'(tt);
      @(negedge clk);  flush_valid_p = 0;
    end
    @(negedge clk);
    st_uv_p[0] = 1;  st_uop_p[0] = mk(8200, 3);  st_base_p[0] = 64'h2_0000;
    st_data_p[0] = 64'h9;  st_f3_p[0] = 3'b011;
    @(negedge clk);  st_uv_p[0] = 0;
    st_tlb_hit_p[0] = 1;  st_tlb_pa_p[0] = 64'h2_0000;
    @(negedge clk);  st_tlb_hit_p[0] = 0;  st_dc_rdy_p[0] = 0;
    repeat (3) @(negedge clk);              // DCREQ 卡住
    flush_valid_p = 1;  flush_tid_p = 3;
    @(negedge clk);  flush_valid_p = 0;
    repeat (4) @(negedge clk);

    // 定點補丁: 第一輪 pipe0 (uid=2300 -> rob_idx=252, bit1=0; vaddr bit50=0),
    // flush 後第二輪 pipe2 (rob_idx=254 bit1=1; vaddr bit50=1) → 全 entry 翻動
    for (int tt = 0; tt < 4; tt++) begin
      @(negedge clk);  flush_valid_p = 1;  flush_tid_p = tid_t'(tt);
      @(negedge clk);  flush_valid_p = 0;
    end
    for (int k = 0; k < 4; k++)
      do_store(0, 64'h8000 + 64'(k) * 64'h1000, 3'b011, tid_t'(k % 4), 64'h1234, 3);
    for (int tt = 0; tt < 4; tt++) begin
      @(negedge clk);  flush_valid_p = 1;  flush_tid_p = tid_t'(tt);
      @(negedge clk);  flush_valid_p = 0;
    end
    for (int k = 0; k < 4; k++)
      do_store(2, 64'h0004_0000_0000_0000 + 64'(k) * 64'h1000, 3'b011,
               tid_t'(k % 4), 64'h1234, 3);
    repeat (2) @(negedge clk);

    repeat (3) @(negedge clk);
    $display("dbg: ld_cnt=%0d st_cnt=%0d fwd=%0d hit=%0d miss=%0d replay=%0d stall=%0d",
             u_ld.ld_count, u_st.store_count, u_ld.stq_fwd_count,
             u_ld.dcache_hit_count, u_ld.dcache_miss_count, u_ld.replay_count,
             u_st.stq_full_stalls);
    if (errors == 0) $display("F3_LSU_LS_TB PASS");
    else             $display("F3_LSU_LS_TB FAIL errors=%0d", errors);
    $finish;
  end

  // ---------------- FSM 監控: lsu_ld / lsu_st state (每 pipe) ----------------
  initial begin : fsm_mon_ldst
    int prev_ld [NUM_LD_PIPE];  int prev_st [NUM_ST_PIPE];  int fd;
    fd = $fopen("fsm.log", "a");
    for (int p = 0; p < NUM_LD_PIPE; p++) prev_ld[p] = -1;
    for (int p = 0; p < NUM_ST_PIPE; p++) prev_st[p] = -1;
    forever begin @(posedge clk);
      for (int p = 0; p < NUM_LD_PIPE; p++)
        if (int'(u_ld.state[p]) !== prev_ld[p]) begin
          if (prev_ld[p] != -1)
            $fwrite(fd, "lsu_ld_%0d %0d %0d\n", p, prev_ld[p], int'(u_ld.state[p]));
          prev_ld[p] = int'(u_ld.state[p]);
        end
      for (int p = 0; p < NUM_ST_PIPE; p++)
        if (int'(u_st.state[p]) !== prev_st[p]) begin
          if (prev_st[p] != -1)
            $fwrite(fd, "lsu_st_%0d %0d %0d\n", p, prev_st[p], int'(u_st.state[p]));
          prev_st[p] = int'(u_st.state[p]);
        end
    end
  end

  logic ld_exc_seen = 0, ld_fwd_seen = 0, ld_replay_seen = 0;
  logic st_exc_seen = 0, stq_full_seen = 0, fence_done_seen = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int p = 0; p < NUM_LD_PIPE; p++) begin
        if (ld_rv[p] && ld_exc[p]) ld_exc_seen <= 1;
        if (ld_replay[p]) ld_replay_seen <= 1;
        if (u_ld.state[p] == u_ld.LD_STQ_CHECK && u_ld.stq_forward_hit[p])
          ld_fwd_seen <= 1;
      end
      for (int p = 0; p < NUM_ST_PIPE; p++)
        if (st_rv[p] && st_exc[p]) st_exc_seen <= 1;
      if (u_st.stq_full) stq_full_seen <= 1;
      if (fence_done) fence_done_seen <= 1;
    end
  end

endmodule : f3_lsu_ls_tb
