// ORCA v6.3 ZEN++ - coverage TB (agent f3)
// f3_rnu_isu_tb: rnu_rat / rnu_remap / rnu_freelist / isu_int 單元 coverage
`include "orca_pkg.sv"

module f3_rnu_isu_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  int errors = 0;
  logic soup_en = 0;   // toggle blitz: clocked soup mirror enable

  // ======================= rnu_remap (含 rat + freelist) =======================
  uop_t [DECODE_WIDTH-1:0] in_uop;
  logic [DECODE_WIDTH-1:0] in_valid, in_ready, out_valid, disp_ready;
  uop_t [DECODE_WIDTH-1:0] out_uop;
  logic br_mispredict;
  rob_idx_t br_rob_idx;
  tid_t br_tid;
  logic flush_valid;
  tid_t flush_tid;
  phys_reg_idx_t flush_map [32];
  logic [RETIRE_WIDTH-1:0] rt_req;
  phys_reg_idx_t [RETIRE_WIDTH-1:0] rt_prd_old;

  rnu_remap u_remap (
    .clk(clk), .rst_n(rst_n),
    .in_uop(in_uop), .in_valid(in_valid), .in_ready(in_ready),
    .out_uop(out_uop), .out_valid(out_valid), .disp_ready(disp_ready),
    .br_mispredict(br_mispredict), .br_rob_idx(br_rob_idx), .br_tid(br_tid),
    .flush_valid(flush_valid), .flush_tid(flush_tid), .flush_map(flush_map),
    .rt_req(rt_req), .rt_prd_old(rt_prd_old));

  // ======================= rnu_rat (standalone, 直打 checkpoint 各路徑) =======================
  tid_t [DISPATCH_WIDTH-1:0] r_tid;
  arch_reg_idx_t [DISPATCH_WIDTH-1:0] r_rs1a, r_rs2a, r_rda;
  logic [DISPATCH_WIDTH-1:0] r_we, r_fp;
  phys_reg_idx_t [DISPATCH_WIDTH-1:0] r_prd, r_prs1, r_prs2, r_pold;
  logic ckpt_push;  tid_t ckpt_tid;  logic [1:0] ckpt_id;
  logic ckpt_restore;  tid_t restore_tid;  logic [1:0] restore_id;
  logic flush_thread;  tid_t rflush_tid;
  phys_reg_idx_t rflush_map [32];

  rnu_rat u_rat (
    .clk(clk), .rst_n(rst_n),
    .tid_i(r_tid), .rs1a(r_rs1a), .rs2a(r_rs2a), .rda(r_rda),
    .rd_we(r_we), .prd_i(r_prd), .is_fp(r_fp),
    .prs1_o(r_prs1), .prs2_o(r_prs2), .prd_old_o(r_pold),
    .ckpt_push(ckpt_push), .ckpt_tid(ckpt_tid), .ckpt_id(ckpt_id),
    .ckpt_restore(ckpt_restore), .restore_tid(restore_tid),
    .restore_id(restore_id),
    .flush_thread(flush_thread), .flush_tid(rflush_tid),
    .flush_map(rflush_map));

  // ======================= isu_int =======================
  uop_t [DISPATCH_WIDTH-1:0] s_uop;
  logic [DISPATCH_WIDTH-1:0] s_valid, s_ready;
  uop_t [NUM_INT_ALU-1:0] i_uop;
  logic [NUM_INT_ALU-1:0] i_valid, i_ready;
  phys_reg_idx_t [7:0] wk_tag;
  logic [7:0] wk_valid;
  logic flush_sched;

  isu_int u_isu (
    .clk(clk), .rst_n(rst_n),
    .disp_uop(s_uop), .disp_valid(s_valid), .disp_ready(s_ready),
    .issue_uop(i_uop), .issue_valid(i_valid), .issue_ready(i_ready),
    .wk_tag(wk_tag), .wk_valid(wk_valid), .flush_valid(flush_sched));

  function automatic uop_t mk(input int uid, input tid_t t, input logic [4:0] rd,
                              input logic [4:0] rs1, input logic [4:0] rs2,
                              input logic fp, input logic st, input logic br,
                              input opcode_type_t op);
    uop_t u;
    u = `UOP_NOP;
    u.opcode = op;  u.rd = rd;  u.rs1 = rs1;  u.rs2 = rs2;
    u.prs1 = phys_reg_idx_t'(uid * 3 + 40);
    u.prs2 = phys_reg_idx_t'(uid * 3 + 41);
    u.is_fp = fp;  u.is_store = st;  u.is_branch = br;
    u.tid = t;  u.uop_id = 16'(uid);
    u.pc = 64'(uid * 4);
    return u;
  endfunction

  initial begin
    $display("F3_RNU_ISU BOOT");
    in_valid = '0;  disp_ready = '1;
    br_mispredict = 0;  br_rob_idx = '0;  br_tid = 0;
    flush_valid = 0;  flush_tid = 0;
    for (int a = 0; a < 32; a++) flush_map[a] = phys_reg_idx_t'(a);
    rt_req = '0;
    for (int i = 0; i < RETIRE_WIDTH; i++) rt_prd_old[i] = phys_reg_idx_t'(0);
    r_we = '0;  r_fp = '0;
    ckpt_push = 0;  ckpt_tid = 0;
    ckpt_restore = 0;  restore_tid = 0;  restore_id = 0;
    flush_thread = 0;  rflush_tid = 0;
    for (int a = 0; a < 32; a++) rflush_map[a] = phys_reg_idx_t'(100 + a);
    for (int i = 0; i < DISPATCH_WIDTH; i++) begin
      r_tid[i] = 0;  r_rs1a[i] = 0;  r_rs2a[i] = 0;  r_rda[i] = 0;
      r_prd[i] = phys_reg_idx_t'(200 + i);
    end
    s_valid = '0;  i_ready = '0;
    wk_valid = '0;
    for (int i = 0; i < 8; i++) wk_tag[i] = phys_reg_idx_t'(0);
    flush_sched = 0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // ------------------------------------------------------------------
    // REMAP: int/fp/store/branch/fence alloc + ckpt + restore + flush
    // ------------------------------------------------------------------
    $display("REMAP phase");
    @(negedge clk);
    for (int i = 0; i < DECODE_WIDTH; i++) begin
      in_valid[i] = 1'b1;
      in_uop[i] = mk(100 + i, tid_t'(i % 4), 5'(i + 1), 5'(i + 2), 5'(i + 3),
                     (i == 2), (i == 3), (i == 0), OP_ALU);
    end
    in_uop[4].opcode = OP_FENCE;   // fence: 不配置 prd
    #1;
    for (int i = 0; i < DECODE_WIDTH; i++)
      if (in_valid[i] && !in_ready[i]) begin
        errors++; $display("ERR: remap not ready slot %0d", i);
      end
    // 註: Verilator BLKLOOPINIT 下 freelist pool 陣列 reset 初始化被略過
    //     (全 0), 屬模擬器行為; 此處僅檢查 prd 與 freelist 輸出一致
    if (out_uop[1].prd !== u_remap.prd_f[1]) begin
      errors++; $display("ERR: prd mismatch");
    end
    $display("  dbg remap: rdy=%0b gnt=%0b need=%0b prd0=%0d prd1=%0d cnt=%0d",
             in_ready, u_remap.gnt, u_remap.need_rd, out_uop[0].prd, out_uop[1].prd,
             u_remap.u_fl.cnt);
    $display("  dbg fl: rd=%0d pool0=%0d pool1=%0d pool2=%0d prdf1=%0d",
             u_remap.u_fl.rd, u_remap.u_fl.pool[0], u_remap.u_fl.pool[1],
             u_remap.u_fl.pool[2], u_remap.prd_f[1]);
    if (out_uop[3].prd != 0) begin errors++; $display("ERR: store alloc"); end
    @(posedge clk); #1 in_valid = '0;

    // dealloc (freelist free): prd >= 32 與 < 32 兩種
    @(negedge clk);
    for (int i = 0; i < RETIRE_WIDTH; i++) begin
      rt_req[i] = 1'b1;
      rt_prd_old[i] = phys_reg_idx_t'(300 + i);
    end
    rt_prd_old[15] = phys_reg_idx_t'(5);   // <32: 不回收
    @(posedge clk); #1 rt_req = '0;

    // branch checkpoint push (slot0 is_branch) -> 之後 mispredict restore
    @(negedge clk);
    in_valid[0] = 1;
    in_uop[0] = mk(200, 2, 5'd9, 5'd1, 5'd2, 0, 0, 1, OP_BRANCH);
    @(posedge clk); #1 in_valid = '0;
    @(negedge clk);
    br_mispredict = 1;  br_tid = 2;  br_rob_idx = 10'd7;
    @(posedge clk); #1 br_mispredict = 0;

    // trap flush: freelist 全量重建 + rat flush_thread
    @(negedge clk);
    flush_valid = 1;  flush_tid = 1;
    for (int a = 0; a < 32; a++) flush_map[a] = phys_reg_idx_t'(a);  // map=identity
    @(posedge clk); #1 flush_valid = 0;
    repeat (2) @(negedge clk);

    // ------------------------------------------------------------------
    // RAT standalone: fp 寫 / 同拍 forwarding / ckpt push-restore / flush
    // ------------------------------------------------------------------
    $display("RAT phase");
    @(negedge clk);
    // slot0 寫 x5 (int, tid0), slot1 讀 x5 (同拍 forward), slot2 fp 寫 f6
    r_we[0] = 1; r_rda[0] = 5; r_prd[0] = phys_reg_idx_t'(150); r_fp[0] = 0;
    r_we[1] = 0; r_rs1a[1] = 5; r_rs2a[1] = 5; r_fp[1] = 0;
    r_we[2] = 1; r_rda[2] = 6; r_prd[2] = phys_reg_idx_t'(160); r_fp[2] = 1;
    r_tid[0] = 0;  r_tid[1] = 0;  r_tid[2] = 1;
    #1;
    if (r_prs1[1] !== phys_reg_idx_t'(150)) begin
      errors++; $display("ERR: rat forward prs1=%0d", r_prs1[1]);
    end
    if (r_prs2[1] !== phys_reg_idx_t'(150)) begin
      errors++; $display("ERR: rat forward prs2");
    end
    @(posedge clk); #1 r_we = '0;
    // 讀回確認
    @(negedge clk);
    r_rs1a[1] = 5; r_fp[1] = 0; r_tid[1] = 0;
    #1;
    if (r_prs1[1] !== phys_reg_idx_t'(150)) begin
      errors++; $display("ERR: rat readback");
    end
    // fp readback (tid1 f6)
    r_rs1a[1] = 6; r_fp[1] = 1; r_tid[1] = 1;
    #1;
    if (r_prs1[1] !== phys_reg_idx_t'(160)) begin
      errors++; $display("ERR: frat readback");
    end
    // checkpoint push x2 (不同 tid), restore
    @(negedge clk);
    ckpt_push = 1;  ckpt_tid = 0;
    @(posedge clk); #1;
    if (ckpt_id !== 2'd1) begin errors++; $display("ERR: ckpt_id after push"); end
    @(negedge clk);
    ckpt_push = 1;  ckpt_tid = 3;
    @(posedge clk); #1 ckpt_push = 0;
    // 修改 tid0 x5 -> 170, 再 restore id0 應回到 150
    @(negedge clk);
    r_we[0] = 1; r_rda[0] = 5; r_prd[0] = phys_reg_idx_t'(170);
    r_fp[0] = 0; r_tid[0] = 0;
    @(posedge clk); #1 r_we = '0;
    @(negedge clk);
    ckpt_restore = 1;  restore_tid = 0;  restore_id = 0;
    @(posedge clk); #1 ckpt_restore = 0;
    @(negedge clk);
    r_rs1a[1] = 5; r_fp[1] = 0; r_tid[1] = 0; #1;
    if (r_prs1[1] !== phys_reg_idx_t'(150)) begin
      errors++; $display("ERR: ckpt restore val=%0d", r_prs1[1]);
    end
    // flush_thread
    @(negedge clk);
    flush_thread = 1;  rflush_tid = 2;
    @(posedge clk); #1 flush_thread = 0;
    @(negedge clk);
    r_rs1a[1] = 7; r_fp[1] = 0; r_tid[1] = 2; #1;
    if (r_prs1[1] !== phys_reg_idx_t'(107)) begin
      errors++; $display("ERR: flush_thread map val=%0d", r_prs1[1]);
    end

    // ------------------------------------------------------------------
    // ISU: ready dispatch / 多 port issue / wakeup / full / flush
    // ------------------------------------------------------------------
    $display("ISU phase");
    @(negedge clk);
    i_ready = '1;
    // ready uops (rs1=rs2=0), uop_id 遞增, 一次 8 筆 → 4 port 同時發射
    for (int i = 0; i < 8; i++) begin
      s_valid[i] = 1;
      s_uop[i] = mk(300 + i, 0, 5'd1, 5'd0, 5'd0, 0, 0, 0, OP_ALU);
    end
    @(posedge clk); #1 s_valid = '0;
    repeat (3) @(negedge clk);
    // wakeup: rs1/rs2 != 0 → 等 wake
    @(negedge clk);
    s_valid[0] = 1;
    s_uop[0] = mk(400, 0, 5'd3, 5'd7, 5'd8, 0, 0, 0, OP_ALU);
    s_uop[0].prs1 = phys_reg_idx_t'(111);
    s_uop[0].prs2 = phys_reg_idx_t'(122);
    @(posedge clk); #1 s_valid = '0;
    repeat (2) @(negedge clk);
    wk_valid[0] = 1;  wk_tag[0] = phys_reg_idx_t'(111);
    @(posedge clk); #1;
    wk_valid[0] = 0;  wk_valid[1] = 1;  wk_tag[1] = phys_reg_idx_t'(122);
    @(posedge clk); #1 wk_valid = '0;
    repeat (3) @(negedge clk);
    // full: 塞滿 64 項 (issue_ready=0)
    // 註: isu_sched insert 迴圈所有 slot 看同一拍 vld, 每拍實際只插 1 筆
    //     (RTL 特性), 故以單 slot 連送 70 拍填滿
    @(negedge clk);
    i_ready = '0;
    for (int c = 0; c < 70; c++) begin
      s_valid[0] = 1;
      s_uop[0] = mk(500 + c, 0, 5'd1, 5'd0, 5'd0, 0, 0, 0, OP_ALU);
      @(posedge clk); #1;
    end
    s_valid = '0;
    repeat (2) @(negedge clk);
    $display("  dbg isu: full=%0b vld0=%0b vld63=%0b", u_isu.u0.full,
             u_isu.u0.vld[0], u_isu.u0.vld[63]);
    if (!full_seen) begin errors++; $display("ERR: sched full never seen"); end
    // flush
    @(negedge clk);
    flush_sched = 1;
    @(posedge clk); #1 flush_sched = 0;
    repeat (2) @(negedge clk);
    for (int i = 0; i < INT_SCHED_DEPTH; i++)
      if (u_isu.u0.vld[i]) begin
        errors++; $display("ERR: flush did not clear sched entry %0d", i);
      end

    // ================= toggle blitz (功能檢查已畢, 僅翻覆蓋) =================
    // 註: --timing 下 initial 直驅的 DUT input port 不計 toggle,
    //     必須以 always_ff 鏡像 (soup_en) 驅動
    $display("toggle blitz: wide-random soup (clocked mirror)");
    soup_en = 1;
    repeat (80) @(negedge clk);
    soup_en = 0;
    @(negedge clk);
    in_valid = '0;  rt_req = '0;  r_we = '0;
    ckpt_push = 0;  ckpt_restore = 0;  flush_thread = 0;
    flush_valid = 0;  br_mispredict = 0;
    s_valid = '0;  wk_valid = '0;  flush_sched = 0;
    disp_ready = '1;
    repeat (4) @(negedge clk);

    // ISU directed: 先 flush 清空, i_ready=0 逐拍塞 8 筆 ready uop,
    // 再 i_ready='1 → 4 port 同時 issue (RTL 每拍僅插 1 筆, 需先囤積)
    @(negedge clk);
    flush_sched = 1;
    @(posedge clk); #1 flush_sched = 0;
    @(negedge clk);
    i_ready = '0;
    for (int c = 0; c < 8; c++) begin
      s_valid[0] = 1;
      s_uop[0] = mk(9100 + c, tid_t'(c % 4), 5'(c + 1), 5'd0, 5'd0, 0, 0, 0, OP_ALU);
      @(posedge clk); #1;
    end
    s_valid = '0;
    @(negedge clk);
    i_ready = '1;                       // 4 port 同時發射
    #1 $display("  dbg issue: iv=%0b vld7..0=%0b%0b%0b%0b%0b%0b%0b%0b",
                {u_isu.u0.issue_valid[3], u_isu.u0.issue_valid[2],
                 u_isu.u0.issue_valid[1], u_isu.u0.issue_valid[0]},
                u_isu.u0.vld[7], u_isu.u0.vld[6], u_isu.u0.vld[5], u_isu.u0.vld[4],
                u_isu.u0.vld[3], u_isu.u0.vld[2], u_isu.u0.vld[1], u_isu.u0.vld[0]);
    repeat (4) @(negedge clk);
    i_ready = '0;

    // freelist cnt/rd/wr poke+event: poke '1 後 alloc+dealloc → 賦值點觀測 1->0
    u_remap.u_fl.cnt = '1;  u_remap.u_fl.rd = '1;  u_remap.u_fl.wr = '1;
    @(negedge clk);
    in_valid[0] = 1;  in_uop[0] = mk(9500, 0, 5'd9, 5'd0, 5'd0, 0, 0, 0, OP_ALU);
    @(posedge clk); #1 in_valid = '0;
    @(negedge clk);
    rt_req[0] = 1;  rt_prd_old[0] = phys_reg_idx_t'(77);
    @(posedge clk); #1 rt_req = '0;
    // 反向: poke '0 後再一次 (0->1)
    u_remap.u_fl.cnt = '0;  u_remap.u_fl.rd = '0;  u_remap.u_fl.wr = '0;
    @(negedge clk);
    in_valid[0] = 1;  in_uop[0] = mk(9600, 1, 5'd8, 5'd0, 5'd0, 0, 0, 0, OP_ALU);
    @(posedge clk); #1 in_valid = '0;
    @(negedge clk);
    rt_req[0] = 1;  rt_prd_old[0] = phys_reg_idx_t'(88);
    @(posedge clk); #1 rt_req = '0;
    // pool source-reg poke: rd=0 後 pool[0..7] 翻動傳播至 alloc_prd 輸出
    u_remap.u_fl.rd = '0;
    for (int i = 0; i < 8; i++) begin
      u_remap.u_fl.pool[i] = '1; #1; u_remap.u_fl.pool[i] = '0; #1;
    end
    repeat (2) @(negedge clk);

    repeat (3) @(negedge clk);
    if (errors == 0) $display("F3_RNU_ISU_TB PASS");
    else             $display("F3_RNU_ISU_TB FAIL errors=%0d", errors);
    $finish;
  end

  logic full_seen = 0;
  always_ff @(posedge clk) begin
    if (rst_n && u_isu.u0.full) full_seen <= 1'b1;
  end

  // ---------------- toggle soup 鏡像: 全輸入每拍隨機 ----------------
  always_ff @(posedge clk) begin
    if (soup_en) begin
      for (int i = 0; i < DECODE_WIDTH; i++) begin
        in_valid[i] <= 1'($urandom);
        in_uop[i]   <= uop_t'({16{$urandom}});
      end
      disp_ready <= DECODE_WIDTH'($urandom);
      br_mispredict <= 1'($urandom);  br_rob_idx <= rob_idx_t'($urandom);
      br_tid <= tid_t'($urandom);
      flush_valid <= 1'($urandom);  flush_tid <= tid_t'($urandom);
      for (int a = 0; a < 32; a++) flush_map[a] <= phys_reg_idx_t'($urandom);
      rt_req <= RETIRE_WIDTH'($urandom);
      for (int i = 0; i < RETIRE_WIDTH; i++)
        rt_prd_old[i] <= phys_reg_idx_t'($urandom);
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        r_we[i] <= 1'($urandom);  r_fp[i] <= 1'($urandom);
        r_rs1a[i] <= arch_reg_idx_t'($urandom);
        r_rs2a[i] <= arch_reg_idx_t'($urandom);
        r_rda[i]  <= arch_reg_idx_t'($urandom);
        r_prd[i]  <= phys_reg_idx_t'($urandom);
        r_tid[i]  <= tid_t'($urandom);
      end
      ckpt_push <= 1'($urandom);  ckpt_tid <= tid_t'($urandom);
      ckpt_restore <= 1'($urandom);  restore_tid <= tid_t'($urandom);
      restore_id <= 2'($urandom);
      flush_thread <= 1'($urandom);  rflush_tid <= tid_t'($urandom);
      for (int a = 0; a < 32; a++) rflush_map[a] <= phys_reg_idx_t'($urandom);
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        s_valid[i] <= 1'($urandom);
        s_uop[i]   <= uop_t'({16{$urandom}});
      end
      i_ready <= NUM_INT_ALU'($urandom);
      wk_valid <= 8'($urandom);
      for (int i = 0; i < 8; i++) wk_tag[i] <= phys_reg_idx_t'($urandom);
      flush_sched <= 1'($urandom);
    end
  end

endmodule : f3_rnu_isu_tb
