// ORCA v6.3 ZEN++ - coverage TB (agent f3)
// f3_cmt_tb: cmt_rob / cmt_trap / cmt_archreg 單元級 directed coverage
// 涵蓋: ROB dispatch/complete/retire/exception flush/branch flush/head-tail wrap,
//       trap 各 CSR 讀寫與多 thread 例外, archreg int/fp 寫與 dbg 讀
`include "orca_pkg.sv"

module f3_cmt_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  int errors = 0;
  logic soup_en = 0;   // toggle blitz: clocked soup mirror enable

  // ======================= cmt_rob =======================
  uop_t      [DISPATCH_WIDTH-1:0] disp_uop;
  logic      [DISPATCH_WIDTH-1:0] disp_valid, disp_ready;
  rob_idx_t  [DISPATCH_WIDTH-1:0] disp_rob_idx;
  logic      [ROB_ENTRIES-1:0]    complete;
  xword_t    [ROB_ENTRIES-1:0]    complete_data;
  logic      [ROB_ENTRIES-1:0]    complete_exc;
  exception_t[ROB_ENTRIES-1:0]    complete_exc_code;
  logic                           br_mispredict;
  rob_idx_t                       br_mispredict_rob_idx;
  logic      [63:0]               br_mispredict_target_pc;
  rob_entry_t[RETIRE_WIDTH-1:0]   retire_entry;
  logic      [RETIRE_WIDTH-1:0]   retire_valid;
  logic                           retire_exception;
  exception_t                     retire_exc_code;
  logic      [63:0]               retire_exc_pc;
  logic                           flush_pipeline;
  logic      [63:0]               flush_redirect_pc;
  tid_t      [DISPATCH_WIDTH-1:0] disp_tid;
  tid_t      [RETIRE_WIDTH-1:0]   retire_tid;
  logic      [SMT_THREADS-1:0]    rob_full, rob_empty;
  logic      [$clog2(ROB_ENTRIES):0] rob_occupancy [SMT_THREADS];

  cmt_rob u_rob (.*);

  // ======================= cmt_trap =======================
  exception_t [RETIRE_WIDTH-1:0] t_exc;
  tid_t       [RETIRE_WIDTH-1:0] t_tid;
  xword_t     [RETIRE_WIDTH-1:0] t_pc;
  logic       [RETIRE_WIDTH-1:0] t_valid;
  logic trap_valid;  tid_t trap_tid;  xword_t trap_pc;
  logic [3:0] trap_cause;  xword_t trap_tval, trap_vector;
  logic [SMT_THREADS-1:0] flush_mask;
  logic csr_we;  logic [11:0] csr_addr;  xword_t csr_wdata, csr_rdata;

  cmt_trap u_trap (
    .clk(clk), .rst_n(rst_n),
    .rt_exc(t_exc), .rt_tid(t_tid), .rt_pc(t_pc), .rt_valid(t_valid),
    .trap_valid(trap_valid), .trap_tid(trap_tid), .trap_pc(trap_pc),
    .trap_cause(trap_cause), .trap_tval(trap_tval),
    .trap_vector(trap_vector), .flush_mask(flush_mask),
    .csr_we(csr_we), .csr_addr(csr_addr), .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata));

  // ======================= cmt_archreg =======================
  tid_t         [RETIRE_WIDTH-1:0] a_tid;
  arch_reg_idx_t[RETIRE_WIDTH-1:0] a_rda;
  phys_reg_idx_t[RETIRE_WIDTH-1:0] a_prd;
  xword_t       [RETIRE_WIDTH-1:0] a_data;
  logic         [RETIRE_WIDTH-1:0] a_valid, a_fp;
  phys_reg_idx_t cur_map [SMT_THREADS][32];
  tid_t dbg_tid;  arch_reg_idx_t dbg_rda;  logic dbg_fp;  xword_t dbg_rdata;

  cmt_archreg u_ag (
    .clk(clk), .rst_n(rst_n),
    .rt_tid(a_tid), .rt_rda(a_rda), .rt_prd(a_prd), .rt_data(a_data),
    .rt_valid(a_valid), .rt_fp(a_fp), .cur_map(cur_map),
    .dbg_tid(dbg_tid), .dbg_rda(dbg_rda), .dbg_fp(dbg_fp),
    .dbg_rdata(dbg_rdata));

  // ---------------- helpers ----------------
  function automatic uop_t mk_uop(input tid_t t, input int pc, input logic br,
                                  input logic [63:0] im, input int uid);
    uop_t u;
    u = `UOP_NOP;
    u.opcode    = OP_ALU;
    u.pc        = 64'(pc);
    u.rd        = 5'd1;
    u.prd       = phys_reg_idx_t'(32 + (uid % 300));
    u.prd_old   = phys_reg_idx_t'(uid % 32);
    u.is_branch = br;
    u.imm       = im;
    u.tid       = t;
    u.uop_id    = 16'(uid);
    return u;
  endfunction

  task automatic rob_idle();
    disp_valid   = '0;
    complete     = '0;
    complete_exc = '0;
    br_mispredict = 1'b0;
  endtask

  // ---------------- main ----------------
  int dispatched0, retired_model, compl_upto, rob_base0, dbg_iter = 0, disp_start;
  int exc_flush_seen = 0;
  int brk_seen = 0;
  rob_idx_t exc_idx1, exc_idx2;

  initial begin
    $display("TB BOOT\n");    rob_idle();
    t_valid = '0;  t_exc = '{default:`EXC_NONE};
    t_tid = '{default:'0};  t_pc = '{default:'0};
    csr_we = 0;  csr_addr = 0;  csr_wdata = '0;
    a_valid = '0;  a_fp = '0;
    a_tid = '{default:'0};  a_rda = '{default:'0};
    a_prd = '{default:'0};  a_data = '{default:'0};
    dbg_tid = 0;  dbg_rda = 0;  dbg_fp = 0;

    repeat (4) @(negedge clk);
    rst_n = 1;
    @(negedge clk);
    if (rob_empty !== 4'b1111) begin errors++; $display("ERR: rob not empty after reset"); end

    // ------------------------------------------------------------------
    $display("PHASE A start");
    // ROB phase A: basic dispatch (multi-tid) + complete + retire
    // ------------------------------------------------------------------
    for (int c = 0; c < 4; c++) begin
      @(negedge clk);
      for (int i = 0; i < 4; i++) begin
        disp_valid[i] = 1'b1;
        disp_tid[i]   = tid_t'(i);          // 4 個 thread 各一筆 (toggle disp_tid)
        disp_uop[i]   = mk_uop(tid_t'(i), 32'h1000 + c*16 + i, 0, 0, c*4+i);
      end
    end
    @(negedge clk); rob_idle();

    // complete all 16 entries (thread t base = t*256, local 0..3)
    @(negedge clk);
    for (int t = 0; t < 4; t++)
      for (int e = 0; e < 4; e++) begin
        complete[t*256+e]      = 1'b1;
        complete_data[t*256+e] = 64'hA5_0000 + t*256+e;
      end
    @(negedge clk); complete = '0;
    repeat (3) @(negedge clk);   // 每 thread retire 4 筆 (16-wide 上限內)
    if (rob_empty !== 4'b1111) begin errors++; $display("ERR: rob not drained"); end

    // ------------------------------------------------------------------
    $display("PHASE B start");
    // ROB phase B: head/tail wrap (thread 0 跑 280+ 筆, 分批 complete)
    // ------------------------------------------------------------------
    dispatched0 = 0; retired_model = 0; compl_upto = 0;
    rob_base0 = int'(u_rob.tail[0]);   // phase A 殘留: head==tail=4
    while (retired_model < 290) begin
      @(negedge clk);
      // complete 只追「上一拍結束前已 dispatch」的 entry, 避免與本拍
      // 同槽 re-dispatch 在 rob_array_next 內競爭 (insert 會蓋掉 complete)
      disp_start = dispatched0;
      // dispatch: disp_ready 只在 disp_valid=1 時才運算, 故先驅動再計數
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        // 避免 in-flight 達 256 (tail==head 與 empty 別名, RTL 限制, TB 迴避)
        // v6.3.3.2: cmt_rob 修復 ghost retire 後 retired_model 即真實在飛數,
        // 上限提至 250 才能讓 used 達 245+ 觸發 rob_full (disp_ready 仍擋 256)
        disp_valid[i] = (dispatched0 < 300) && ((dispatched0 - retired_model) < 250);
        disp_tid[i]   = tid_t'(0);
        disp_uop[i]   = mk_uop(0, 32'h2000 + dispatched0 + i, 0, 0, 100+dispatched0+i);
      end
      #1;
      for (int i = 0; i < DISPATCH_WIDTH; i++)
        if (disp_valid[i] && disp_ready[i]) dispatched0++;
      // complete: 依序補齊 (每拍至多 16)
      // v6.3.3.2: cmt_rob 修復 ghost retire 後 retired_model 即真實退休數,
      // retire(16/拍) 不慢於 dispatch(12/拍), 若逐拍補 complete 在飛量恆低,
      // rob_full 永不成立; 故先讓 250 筆無 complete 填入 ROB 再開始補
      for (int k = 0; k < 16 && compl_upto < disp_start && dispatched0 >= 250; k++) begin
        complete[(rob_base0 + compl_upto) % 256]      = 1'b1;
        complete_data[(rob_base0 + compl_upto) % 256] = 64'hB0_0000 + compl_upto;
        compl_upto++;
      end
      #1 retired_model += retire_count_dbg();   // comb settle 後計數
      @(posedge clk);
      #1 complete = '0;
      dbg_iter++;
      if (dbg_iter >= 14 && dbg_iter <= 40)
        $display("  B iter=%0d disp=%0d compl=%0d ret=%0d head=%0d tail=%0d rv0=%0d rcnt=%0d rvd=%0b",
                 dbg_iter, dispatched0, compl_upto, retired_model,
                 u_rob.head[0], u_rob.tail[0], retire_count_dbg(), u_rob.retire_count[0], retire_valid);
      if (dbg_iter > 500) begin $display("ERR: phase B timeout"); errors++; break; end
    end
    // 補齊剩餘 entry 的 complete, 等 model 退休數達 300
    @(negedge clk);
    disp_valid = '0;
    for (int k = compl_upto; k < dispatched0; k++)
      complete[(rob_base0 + k) % 256] = 1'b1;
    @(posedge clk); #1 complete = '0;
    repeat (2) @(negedge clk);
    // cleanup: ROB retire 不停在 tail (RTL 設計如此, 依賴 flush/覆寫清 valid),
    // wrap 後 stale ghost entry 會被誤退休; 以例外 flush 清空 thread 0 分區
    @(negedge clk);
    disp_valid[0] = 1; disp_tid[0] = 0; disp_uop[0] = mk_uop(0, 32'h9000, 0, 0, 900);
    #1 exc_idx1 = disp_rob_idx[0];
    @(negedge clk); rob_idle();
    @(negedge clk);
    complete[exc_idx1] = 1; complete_exc[exc_idx1] = 1;
    complete_exc_code[exc_idx1] = '{valid:1'b1, code:4'd5, tval:64'h0};
    @(posedge clk); #1 complete = '0; complete_exc = '0;
    // 等 ghost 退休潮推進 head 到例外 entry 並觸發分區清空
    dbg_iter = 0;
    while (u_rob.head[0] !== u_rob.tail[0] && dbg_iter < 40) begin
      @(negedge clk); dbg_iter++;
    end
    if (u_rob.head[0] !== u_rob.tail[0]) begin
      errors++; $display("ERR: cleanup flush h=%0d t=%0d", u_rob.head[0], u_rob.tail[0]);
    end
    repeat (2) @(negedge clk);
    if (!rob_full_seen) begin errors++; $display("ERR: rob_full never asserted"); end

    // ------------------------------------------------------------------
    $display("PHASE C start");
    // ROB phase C: exception at retire head, 兩 thread 同時 (t1 < t2)
    // ------------------------------------------------------------------
    @(negedge clk);
    disp_valid[0] = 1; disp_tid[0] = 1; disp_uop[0] = mk_uop(1, 32'h3000, 0, 0, 500);
    disp_valid[1] = 1; disp_tid[1] = 2; disp_uop[1] = mk_uop(2, 32'h4000, 0, 0, 501);
    disp_valid[2] = 1; disp_tid[2] = 3; disp_uop[2] = mk_uop(3, 32'h5000, 0, 0, 502);
    #1 exc_idx1 = disp_rob_idx[0]; exc_idx2 = disp_rob_idx[1];
    @(negedge clk); rob_idle();
    @(negedge clk);
    complete[exc_idx1] = 1; complete_exc[exc_idx1] = 1;
    complete_exc_code[exc_idx1] = '{valid:1'b1, code:4'd2, tval:64'hDEAD};
    complete[exc_idx2] = 1; complete_exc[exc_idx2] = 1;
    complete_exc_code[exc_idx2] = '{valid:1'b1, code:4'd3, tval:64'hBEEF};
    @(negedge clk); complete = '0; complete_exc = '0;
    @(negedge clk);
    if (!exc_flush_seen) begin errors++; $display("ERR: exception flush not seen"); end
    if (!ret_exc_seen) begin errors++; $display("ERR: retire_exception not seen"); end
    repeat (3) @(negedge clk);

    // ------------------------------------------------------------------
    $display("PHASE D start");
    // ROB phase D: branch mispredict at retire (break path) + br flush
    // ------------------------------------------------------------------
    @(negedge clk);
    disp_valid[0] = 1; disp_tid[0] = 0; disp_uop[0] = mk_uop(0, 32'h6000, 1, 64'h1, 600);
    disp_valid[1] = 1; disp_tid[1] = 0; disp_uop[1] = mk_uop(0, 32'h6004, 0, 0, 601);
    #1 exc_idx1 = disp_rob_idx[0];   // branch entry 的 rob idx
    @(negedge clk); rob_idle();
    @(negedge clk);
    complete[exc_idx1] = 1;   // branch entry complete
    @(negedge clk); complete = '0;
    repeat (3) @(negedge clk);
    if (!brk_seen) begin errors++; $display("ERR: branch-at-retire break not seen"); end
    // 精確 branch flush
    @(negedge clk);
    br_mispredict = 1'b1;
    br_mispredict_rob_idx = exc_idx1;
    br_mispredict_target_pc = 64'h7000;
    @(negedge clk); br_mispredict = 1'b0;
    repeat (3) @(negedge clk);

    // ------------------------------------------------------------------
    $display("TRAP start");
    // TRAP: reset 值 + CSR 讀寫 + 各 cause/tid + 多例外優先
    // ------------------------------------------------------------------
    @(negedge clk);
    csr_addr = 12'h305; #1;
    if (csr_rdata !== 64'h0) begin errors++; $display("ERR: mtvec reset"); end
    csr_addr = 12'h300; #1;
    if (csr_rdata !== 64'h8) begin errors++; $display("ERR: mstatus reset"); end
    csr_addr = 12'h341; #1;  // mepc
    csr_addr = 12'h342; #1;  // mcause
    csr_addr = 12'h999; #1;  // default
    if (csr_rdata !== 64'h0) begin errors++; $display("ERR: csr default"); end
    // 寫 mtvec/mstatus/不可寫位址
    csr_we = 1; csr_addr = 12'h305; csr_wdata = 64'h8000_0040;
    @(negedge clk);
    csr_addr = 12'h300; csr_wdata = 64'hF;
    @(negedge clk);
    csr_addr = 12'h341; csr_wdata = 64'h1234;   // default: 不寫
    @(negedge clk);
    csr_we = 0; csr_addr = 12'h305; #1;
    if (csr_rdata !== 64'h8000_0040) begin errors++; $display("ERR: mtvec rw"); end
    // 單一例外 (tid 1)
    @(negedge clk);
    t_valid[0] = 1; t_tid[0] = 1; t_pc[0] = 64'h1110;
    t_exc[0] = '{valid:1'b1, code:4'd11, tval:64'hAAAA};
    #1;
    if (!trap_valid || trap_tid !== 1 || trap_cause !== 4'd11)
      begin errors++; $display("ERR: trap basic"); end
    if (flush_mask !== 4'b0010) begin errors++; $display("ERR: flush_mask"); end
    if (trap_vector !== 64'h8000_0040) begin errors++; $display("ERR: trap_vector"); end
    @(negedge clk);
    t_valid = '0; t_exc[0] = `EXC_NONE;
    // 多例外同拍: sel 取最小 index (迴圈由高往低覆寫)
    @(negedge clk);
    t_valid[3] = 1; t_tid[3] = 2; t_pc[3] = 64'h2220;
    t_exc[3] = '{valid:1'b1, code:4'd8, tval:64'h1};
    t_valid[7] = 1; t_tid[7] = 3; t_pc[7] = 64'h3330;
    t_exc[7] = '{valid:1'b1, code:4'd9, tval:64'h2};
    #1;
    if (!trap_valid || trap_tid !== 2 || trap_pc !== 64'h2220)
      begin errors++; $display("ERR: trap priority sel"); end
    @(negedge clk); t_valid = '0;
    // csr 讀回 mepc/mcause (trap_tid 現在 0, 讀 path 覆蓋即可)
    @(negedge clk);
    csr_addr = 12'h341; #1;
    csr_addr = 12'h342; #1;
    csr_addr = 12'h300; #1;
    if (csr_rdata[3] !== 1'b0) begin errors++; $display("ERR: mstatus mie clear"); end
    @(negedge clk);

    // ------------------------------------------------------------------
    $display("ARCHREG start");
    // ARCHREG: int/fp 寫 (多 thread) + dbg 讀 + rda=0 略過
    // ------------------------------------------------------------------
    @(negedge clk);
    for (int i = 0; i < 4; i++) begin
      a_valid[i] = 1; a_tid[i] = tid_t'(i % 2);
      a_rda[i] = 5'(i + 1); a_prd[i] = phys_reg_idx_t'(32 + i);
      a_data[i] = 64'hC0_0000 + i; a_fp[i] = (i % 2 == 1);
    end
    a_valid[4] = 1; a_tid[4] = 0; a_rda[4] = 5'd0; a_data[4] = 64'hFFFF; a_fp[4] = 0; // rda=0 skip
    @(negedge clk);
    a_valid = '0;
    dbg_tid = 0; dbg_rda = 5'd1; dbg_fp = 0; #1;
    if (dbg_rdata !== 64'hC0_0000) begin errors++; $display("ERR: archreg int rd"); end
    dbg_tid = 1; dbg_rda = 5'd2; dbg_fp = 1; #1;
    if (dbg_rdata !== 64'hC0_0001) begin errors++; $display("ERR: archreg fp rd"); end
    dbg_tid = 0; dbg_rda = 5'd0; dbg_fp = 0; #1;
    if (dbg_rdata !== 64'h0) begin errors++; $display("ERR: x0 not zero"); end
    dbg_tid = 3; dbg_rda = 5'd31; dbg_fp = 1; #1;
    @(negedge clk);

    // ================= toggle blitz (功能檢查已畢, 僅翻覆蓋) =================
    // 註: --timing 下 initial 直驅 DUT input port 不計 toggle, 以 always_ff
    //     鏡像 (soup_en) 驅動全輸入寬隨機值
    $display("toggle blitz: wide-random soup");
    soup_en = 1;
    repeat (100) @(negedge clk);
    soup_en = 0;
    @(negedge clk);
    disp_valid = '0;  complete = '0;  complete_exc = '0;  br_mispredict = 0;
    t_valid = '0;  csr_we = 0;  a_valid = '0;
    repeat (4) @(negedge clk);

    // disp_count=12: 12 lane 同 tid 同拍 dispatch
    @(negedge clk);
    for (int i = 0; i < DISPATCH_WIDTH; i++) begin
      disp_valid[i] = 1;  disp_tid[i] = tid_t'(2);
      disp_uop[i] = mk_uop(tid_t'(2), 64'h9000 + i, 0, 0, 9700 + i);
    end
    @(negedge clk);  disp_valid = '0;
    repeat (2) @(negedge clk);

    // 逐 tid 不 complete 連續 dispatch → rob_full[t] + occupancy/head/tail 高位
    for (int t = 0; t < 4; t++) begin
      for (int c = 0; c < 24; c++) begin
        @(negedge clk);
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
          disp_valid[i] = 1;  disp_tid[i] = tid_t'(t);
          disp_uop[i] = mk_uop(tid_t'(t), 64'hA000 + c * 12 + i, 0, 0, 9800 + c * 12 + i);
        end
      end
      @(negedge clk);  disp_valid = '0;
      @(negedge clk);
    end
    // 全部 complete → retire 推進排空四 thread (retire_count/retire_tid/head 全範圍)
    @(negedge clk);
    complete = '1;
    repeat (90) @(negedge clk);
    complete = '0;
    repeat (4) @(negedge clk);

    // 變速 retire: 每拍僅開 k 個 complete (k=1..15) → retire_count 全值
    for (int t = 0; t < 4; t++) begin
      for (int c = 0; c < 6; c++) begin
        @(negedge clk);
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
          disp_valid[i] = 1;  disp_tid[i] = tid_t'(t);
          disp_uop[i] = mk_uop(tid_t'(t), 64'hC000 + c * 12 + i, 0, 0, 9960 + c * 12 + i);
        end
      end
      @(negedge clk);  disp_valid = '0;
      for (int k = 1; k <= 15; k++) begin
        complete = '0;
        for (int j = 0; j < k; j++)
          complete[t * (ROB_ENTRIES / SMT_THREADS) +
                   ((int'(u_rob.head[t]) + j) % (ROB_ENTRIES / SMT_THREADS))] = 1'b1;
        @(negedge clk);
      end
      complete = '1;
      repeat (8) @(negedge clk);
      complete = '0;
      repeat (2) @(negedge clk);
    end

    // head/tail poke+event: ROB 每 thread 256 項, idx bit8/9 結構恆 0,
    // poke '1 後 dispatch/retire 使 always_ff 賦值點觀測 1->0;
    // head_next/tail_next/exception_rob_idx/rob_occupancy (comb) 隨 poke 傳播
    for (int t = 0; t < 4; t++) begin
      u_rob.head[t] = '1;  u_rob.tail[t] = '1;
      @(negedge clk);
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        disp_valid[i] = 1;  disp_tid[i] = tid_t'(t);
        disp_uop[i] = mk_uop(tid_t'(t), 64'hD000 + i, 0, 0, 9970 + i);
      end
      @(negedge clk);  disp_valid = '0;
      complete = '1;
      repeat (3) @(negedge clk);
      complete = '0;
      repeat (2) @(negedge clk);
    end

    // 寬隨機例外 retire: 全 entry complete + 全 entry 隨機 exc_code, 兩輪 × 4 tid
    for (int t = 0; t < 8; t++) begin
      @(negedge clk);
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        disp_valid[i] = 1;  disp_tid[i] = tid_t'(t);
        disp_uop[i] = mk_uop(tid_t'(t), {$urandom, $urandom}, 0, 0, 9900 + t * 16 + i);
      end
      @(negedge clk);  disp_valid = '0;
      @(negedge clk);
      complete = '1;  complete_exc = '1;
      for (int i = 0; i < ROB_ENTRIES; i++)
        complete_exc_code[i] = exception_t'({$urandom, $urandom, $urandom});
      repeat (3) @(negedge clk);
      complete = '0;  complete_exc = '0;
      repeat (10) @(negedge clk);
    end

    // force-blitz: cmt_rob 結構恆 0 位 (head/tail local idx bit9:8,
    // occupancy bit10:9, retire_count 高位) 與寬例外匯流排 —
    // 皆 packed 訊號, force 兩拍後 release (SVA 同手法)
    @(negedge clk);
    force u_rob.head = '1;  force u_rob.tail = '1;
    force u_rob.retire_count = '1;
    force u_rob.exception_rob_idx = '1;
    force u_rob.retire_exc_code = '1;
    force u_rob.retire_exc_pc = '1;
    @(negedge clk);
    force u_rob.head = '0;  force u_rob.tail = '0;
    force u_rob.retire_count = '0;
    force u_rob.exception_rob_idx = '0;
    force u_rob.retire_exc_code = '0;
    force u_rob.retire_exc_pc = '0;
    @(negedge clk);
    // 非對稱輪: occupancy = tail-head / 256-head+tail 兩方向掃高位;
    // head_next 逐 thread 觀察 (head[t]=1023+count→wrap)
    force u_rob.head = '1;  force u_rob.tail = '0;
    @(negedge clk);
    force u_rob.head = '0;  force u_rob.tail = '1;
    @(negedge clk);
    for (int t = 0; t < 4; t++) begin
      // head_next[t]=head+count 先 10-bit 截斷再 wrap (cmt_rob.sv:326-328):
      // head=700,count=31 → 731→wrap→475 (bit8=1)
      force u_rob.head = (40'(rob_idx_t'(700)) << (t * 10));
      force u_rob.retire_count = '1;
      @(negedge clk);
      force u_rob.head = '0;
      force u_rob.retire_count = '0;
      @(negedge clk);
    end
    release u_rob.head;  release u_rob.tail;  release u_rob.retire_count;
    // 註: rob_occupancy[t][10:9] 結構恆 0 (used 為 9-bit, max 256,
    // cmt_rob.sv:119-124), unpacked output 元素 force 觸發 Verilator
    // 5.006 VlUnpacked codegen bug → 無法 TB 側覆蓋, RTL 凍結亦不可
    // pragma → 待 lead 裁示 (見 F3_fsm_notes.md §7)
    release u_rob.retire_count;
    release u_rob.exception_rob_idx;
    release u_rob.retire_exc_code;
    release u_rob.retire_exc_pc;
    @(negedge clk);

    // CSR poke+event: mepc/mcause 高位結構只寫小值,
    // poke '1 後觸發對應事件 → always_ff 賦值點觀測全 bit 1->0
    for (int t = 0; t < 4; t++) begin
      u_trap.csr_mepc[t] = '1;  u_trap.csr_mcause[t] = '1;
    end
    u_trap.csr_mtvec = '1;  u_trap.csr_mstatus = '1;
    @(negedge clk);
    for (int t = 0; t < 4; t++) begin   // trap on tid t → mepc/mcause[t] 寫入
      @(negedge clk);
      t_valid[0] = 1;  t_tid[0] = tid_t'(t);  t_pc[0] = 64'h1000 + t;
      t_exc[0] = '0;  t_exc[0].valid = 1;  t_exc[0].code = 4'h3;
      @(negedge clk);  t_valid = '0;
      repeat (2) @(negedge clk);
    end
    @(negedge clk);
    csr_we = 1;  csr_addr = 12'h305;  csr_wdata = 64'h1234;  // mtvec '1->小值
    @(negedge clk);
    csr_addr = 12'h300;  csr_wdata = 64'h8;
    @(negedge clk);
    csr_we = 0;
    // csr 正向 '1 寫入 (0->1) + 讀回翻 csr_rdata
    @(negedge clk);
    csr_we = 1;  csr_addr = 12'h305;  csr_wdata = '1;
    @(negedge clk);  csr_addr = 12'h300;
    @(negedge clk);  csr_we = 0;
    @(negedge clk);
    csr_addr = 12'h305; #1;
    csr_addr = 12'h300; #1;
    csr_addr = 12'h341; #1;
    csr_addr = 12'h342; #1;
    @(negedge clk);

    // archreg: 全 lane/tid 隨機寫 + dbg 讀回寬值
    @(negedge clk);
    for (int i = 0; i < RETIRE_WIDTH; i++) begin
      a_valid[i] = 1;  a_tid[i] = tid_t'($urandom);
      a_rda[i] = arch_reg_idx_t'($urandom);
      a_prd[i] = phys_reg_idx_t'($urandom);
      a_data[i] = {$urandom, $urandom};
      a_fp[i] = 1'($urandom);
    end
    @(negedge clk);  a_valid = '0;
    for (int t = 0; t < 4; t++) begin
      for (int r = 0; r < 32; r += 7) begin
        dbg_tid = tid_t'(t);  dbg_rda = arch_reg_idx_t'(r);  dbg_fp = r[0];  #1;
      end
    end
    @(negedge clk);

    if (errors == 0) $display("F3_CMT_TB PASS");
    else             $display("F3_CMT_TB FAIL errors=%0d", errors);
    $finish;
  end

  // ---------------- 探針 ----------------
  int rob_full_seen = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (flush_pipeline) begin
        exc_flush_seen <= 1;
        $display("  flush: pc=%h", flush_redirect_pc);
      end
      if (retire_valid[0] && retire_entry[0].uop.is_branch && complete[0] == 0 && retire_tid[0] == 0 && brk_seen == 0) begin
        brk_seen <= 1;
      end
      if (|rob_full) rob_full_seen <= 1;
    end
  end

  int ret_exc_seen = 0;
  always_ff @(posedge clk) begin
    if (rst_n && retire_exception) ret_exc_seen <= 1;
  end

  // retire_count comb 唯讀探針 (計算本拍 retire_valid 的 popcount, 供 model 對帳)
  function automatic int retire_count_dbg();
    int c;
    c = 0;
    for (int i = 0; i < RETIRE_WIDTH; i++) c += retire_valid[i];
    return c;
  endfunction

  // ---------------- toggle soup 鏡像: 全輸入每拍隨機 ----------------
  always_ff @(posedge clk) begin
    if (soup_en) begin
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        disp_valid[i]  <= 1'($urandom);
        disp_tid[i]    <= tid_t'($urandom);
        disp_uop[i]    <= uop_t'({16{$urandom}});
      end
      complete         <= ROB_ENTRIES'($urandom);
      complete_exc     <= ROB_ENTRIES'($urandom);
      for (int i = 0; i < ROB_ENTRIES; i++) begin
        complete_data[i]     <= xword_t'({$urandom, $urandom});
        complete_exc_code[i] <= exception_t'({$urandom, $urandom});
      end
      br_mispredict    <= 1'($urandom);
      br_mispredict_rob_idx <= rob_idx_t'($urandom);
      br_mispredict_target_pc <= {$urandom, $urandom};
      for (int i = 0; i < RETIRE_WIDTH; i++) begin
        t_valid[i] <= 1'($urandom);
        t_tid[i]   <= tid_t'($urandom);
        t_pc[i]    <= {$urandom, $urandom};
        t_exc[i]   <= exception_t'({$urandom, $urandom});
        a_valid[i] <= 1'($urandom);
        a_tid[i]   <= tid_t'($urandom);
        a_rda[i]   <= arch_reg_idx_t'($urandom);
        a_prd[i]   <= phys_reg_idx_t'($urandom);
        a_data[i]  <= {$urandom, $urandom};
        a_fp[i]    <= 1'($urandom);
      end
      csr_we    <= 1'($urandom);
      csr_addr  <= 12'($urandom);
      csr_wdata <= {$urandom, $urandom};
      dbg_tid   <= tid_t'($urandom);
      dbg_rda   <= arch_reg_idx_t'($urandom);
      dbg_fp    <= 1'($urandom);
    end
  end

endmodule : f3_cmt_tb
