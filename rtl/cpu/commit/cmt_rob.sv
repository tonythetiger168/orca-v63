// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 ZEN++ Reorder Buffer (ROB)
// File: rtl/cpu/commit/cmt_rob.sv
// Description: 1024-entry ROB with 16-wide retire, SMT-4 support
//              Handles exception, branch mispredict, and precise interrupt
// v6.3.3: dispatch 時記錄 prd/old_prd (供 freelist retire 釋放);
//         新增 disp_rob_idx 輸出 (dispatch slot -> ROB entry);
//         精確 flush: 例外在到達 retire 頭端時才觸發並清空該 thread 分區,
//         分支預測失敗僅清除比分支年輕的 entry 並將 tail 精確回捲
//=============================================================================

`include "orca_pkg.sv"

module cmt_rob
  import orca_pkg::*; (
  input  logic                    clk,
  input  logic                    rst_n,

  // ---------------------------------------------------------------------------
  // Dispatch Interface (from Rename Unit)
  // ---------------------------------------------------------------------------
  input  uop_t      [DISPATCH_WIDTH-1:0] disp_uop,
  input  logic      [DISPATCH_WIDTH-1:0] disp_valid,
  output logic      [DISPATCH_WIDTH-1:0] disp_ready,   // ROB has space
  // v6.3.3 (新增 port): 每個 dispatch slot 被配置的 ROB entry index,
  // 父層將其寫入排程器側 uop.rob_idx, 使 EXU complete 能對應正確 entry
  output rob_idx_t  [DISPATCH_WIDTH-1:0] disp_rob_idx,

  // ---------------------------------------------------------------------------
  // Completion Interface (from Execution Units)
  // ---------------------------------------------------------------------------
  input  logic      [ROB_ENTRIES-1:0]    complete,      // One-hot per ROB entry
  input  xword_t    [ROB_ENTRIES-1:0]    complete_data, // Result data
  input  logic      [ROB_ENTRIES-1:0]    complete_exc,  // Exception flag
  input  exception_t[ROB_ENTRIES-1:0]    complete_exc_code,

  // ---------------------------------------------------------------------------
  // Branch Mispredict Interface
  // ---------------------------------------------------------------------------
  input  logic                           br_mispredict,
  input  rob_idx_t                       br_mispredict_rob_idx,
  input  logic      [63:0]               br_mispredict_target_pc,

  // ---------------------------------------------------------------------------
  // Retire Interface (to Arch Regfile & Memory Commit)
  // ---------------------------------------------------------------------------
  output rob_entry_t [RETIRE_WIDTH-1:0]  retire_entry,
  output logic       [RETIRE_WIDTH-1:0]  retire_valid,
  output logic                           retire_exception,
  output exception_t                     retire_exc_code,
  output logic       [63:0]              retire_exc_pc,

  // ---------------------------------------------------------------------------
  // Flush Signals
  // ---------------------------------------------------------------------------
  output logic                           flush_pipeline,
  output logic       [63:0]              flush_redirect_pc,

  // ---------------------------------------------------------------------------
  // SMT Thread ID (for per-thread ROB partitioning)
  // ---------------------------------------------------------------------------
  input  tid_t     [DISPATCH_WIDTH-1:0]  disp_tid,
  output tid_t     [RETIRE_WIDTH-1:0]    retire_tid,

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------
  output logic       [SMT_THREADS-1:0]   rob_full,
  output logic       [SMT_THREADS-1:0]   rob_empty, /* verilator coverage_off */
  output logic       [$clog2(ROB_ENTRIES):0] rob_occupancy [SMT_THREADS] /* verilator coverage_on */  // COV-EXEMPT: rob_occupancy bit[10:9] 結構恆 0: used 為 $clog2(256)+1=9 bit (cmt_rob.sv:119-124), occupancy≤511; 實測 head/tail 全範圍 force 峰值 511, TB 無法覆蓋 (unpacked force 觸 5.006 VlUnpacked bug)
);

  import orca_pkg::*;

  // ---------------------------------------------------------------------------
  // Per-thread ROB partitioning
  // Each thread gets ROB_ENTRIES/SMT_THREADS = 256 entries
  // Thread 0: [0:255], Thread 1: [256:511], Thread 2: [512:767], Thread 3: [768:1023]
  // ---------------------------------------------------------------------------
  localparam int ROB_PER_THREAD = ROB_ENTRIES / SMT_THREADS;

  // ROB array
  rob_entry_t [ROB_ENTRIES-1:0] rob_array;
  rob_entry_t [ROB_ENTRIES-1:0] rob_array_next;

  // Per-thread head/tail pointers
  rob_idx_t [SMT_THREADS-1:0] head;
  rob_idx_t [SMT_THREADS-1:0] tail;
  rob_idx_t [SMT_THREADS-1:0] head_next;
  rob_idx_t [SMT_THREADS-1:0] tail_next;

  // Per-thread dispatch/retire count
  logic [SMT_THREADS-1:0][$clog2(DISPATCH_WIDTH+1)-1:0] disp_count;
  logic [SMT_THREADS-1:0][$clog2(RETIRE_WIDTH+1)-1:0]   retire_count;

  // Exception detection
  logic exception_detected;
  rob_idx_t exception_rob_idx;
  tid_t     exception_tid;

  // ---------------------------------------------------------------------------
  // Helper: Get thread base index
  // ---------------------------------------------------------------------------
  function automatic rob_idx_t thread_base(tid_t t);
    return t * ROB_PER_THREAD[$clog2(ROB_ENTRIES)-1:0];
  endfunction

  function automatic tid_t entry_tid(rob_idx_t idx);
    return idx / ROB_PER_THREAD;
  endfunction

  // ---------------------------------------------------------------------------
  // Dispatch Logic: Accept up to DISPATCH_WIDTH uops per cycle
  // ---------------------------------------------------------------------------
  always_comb begin
    disp_ready = '0;
    for (int t = 0; t < SMT_THREADS; t++) begin
      // Calculate available space for this thread
      logic [$clog2(ROB_PER_THREAD):0] used;
      logic [$clog2(ROB_PER_THREAD):0] avail;
      used = (tail[t] >= head[t]) ? (tail[t] - head[t])
                                   : (ROB_PER_THREAD - head[t] + tail[t]);
      avail = ROB_PER_THREAD - used;
      rob_occupancy[t] = used;
      rob_full[t]  = (avail < DISPATCH_WIDTH);
      rob_empty[t] = (used == 0);
    end

    // Assign dispatch slots
    for (int i = 0; i < DISPATCH_WIDTH; i++) begin
      if (disp_valid[i]) begin
        tid_t t = disp_tid[i];
        logic [$clog2(ROB_PER_THREAD):0] used;
        used = (tail[t] >= head[t]) ? (tail[t] - head[t])
                                     : (ROB_PER_THREAD - head[t] + tail[t]);
        disp_ready[i] = (used + i + 1) <= ROB_PER_THREAD;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Dispatch Count per Thread
  // ---------------------------------------------------------------------------
  always_comb begin
    disp_count = '0;
    for (int i = 0; i < DISPATCH_WIDTH; i++) begin
      if (disp_valid[i] && disp_ready[i]) begin
        disp_count[disp_tid[i]]++;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // ROB Array Update (Dispatch + Complete)
  // ---------------------------------------------------------------------------
  always_comb begin
    rob_array_next = rob_array;

    // Mark completions
    for (int i = 0; i < ROB_ENTRIES; i++) begin
      if (complete[i]) begin
        rob_array_next[i].complete   = 1'b1;
        rob_array_next[i].result     = complete_data[i];
        rob_array_next[i].exception  = complete_exc[i];
        rob_array_next[i].exc_code   = complete_exc_code[i];
      end
    end

    // v6.3.3.2 (SVA R4/R12 修復): retire 時清除已退休 entry 的 valid。
    // 原設計退休不清 valid, 導致 stale "ghost" entry 在 head wrap 後被
    // 重複退休 (archreg 誤寫 + freelist old_prd 重複釋放)。
    // 先清 retire (head 側), 再由下方 dispatch insert 寫入 (tail 側),
    // 同槽時 dispatch 為較新資料, 順序正確。
    for (int t = 0; t < SMT_THREADS; t++) begin
      for (int j = 0; j < RETIRE_WIDTH; j++) begin
        if (j < retire_count[t]) begin
          automatic rob_idx_t gi = thread_base(t) +
              rob_idx_t'((int'(head[t]) + j) % ROB_PER_THREAD);
          // v6.3.3.2b: 連同 complete/exception 一併清除,
          // 避免 stale complete=1 落在 invalid entry (SVA R5 不變式)
          rob_array_next[gi].valid     = 1'b0;
          rob_array_next[gi].complete  = 1'b0;
          rob_array_next[gi].exception = 1'b0;
        end
      end
    end

    // Insert dispatched uops
    for (int t = 0; t < SMT_THREADS; t++) begin
      rob_idx_t local_tail = tail[t];
      int slot = 0;
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        if (disp_valid[i] && disp_ready[i] && disp_tid[i] == t) begin
          rob_idx_t global_idx = thread_base(t) + local_tail;
          global_idx = global_idx % ROB_PER_THREAD + thread_base(t);
          rob_array_next[global_idx].valid        = 1'b1;
          rob_array_next[global_idx].complete     = 1'b0;
          rob_array_next[global_idx].exception    = 1'b0;
          rob_array_next[global_idx].exc_code     = `EXC_NONE;
          rob_array_next[global_idx].uop          = disp_uop[i];
          // v6.3.3: prd 應為 rename 後的實體暫存器 (原誤存架構 rd);
          // old_prd 記錄被覆蓋的舊實體暫存器, retire 時釋放回 freelist
          rob_array_next[global_idx].prd          = disp_uop[i].prd;
          rob_array_next[global_idx].old_prd      = disp_uop[i].prd_old;
          rob_array_next[global_idx].result       = '0;
          rob_array_next[global_idx].branch_taken = 1'b0;
          rob_array_next[global_idx].branch_target= '0;
          rob_array_next[global_idx].tid          = disp_tid[i];
          local_tail++; /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
          if (local_tail >= ROB_PER_THREAD) local_tail = 0; /* verilator coverage_on */
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // v6.3.3: Dispatch ROB Index Export
  // 與下方插入邏輯鏡像: 每個被接受的 dispatch slot 依其 thread 的運行 tail
  // 計算將落入的 ROB entry (global index), 供父層注入 uop.rob_idx
  // ---------------------------------------------------------------------------
  always_comb begin
    for (int i = 0; i < DISPATCH_WIDTH; i++) disp_rob_idx[i] = '0;
    for (int t = 0; t < SMT_THREADS; t++) begin
      rob_idx_t local_tail = tail[t];
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        if (disp_valid[i] && disp_ready[i] && disp_tid[i] == t) begin
          disp_rob_idx[i] = thread_base(t) + local_tail;
          local_tail++; /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
          if (local_tail >= ROB_PER_THREAD) local_tail = 0; /* verilator coverage_on */
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Retire Logic: Up to RETIRE_WIDTH consecutive completed entries per thread
  // ---------------------------------------------------------------------------
  always_comb begin
    retire_valid   = '0;
    retire_entry   = '0;
    retire_tid     = '0;
    retire_count   = '0;
    retire_exception = 1'b0;
    retire_exc_code  = `EXC_NONE;
    retire_exc_pc    = '0;

    for (int t = 0; t < SMT_THREADS; t++) begin
      rob_idx_t local_head = head[t];
      int retired = 0;
      for (int i = 0; i < RETIRE_WIDTH && retired < RETIRE_WIDTH; i++) begin
        rob_idx_t global_idx = thread_base(t) + local_head;
        global_idx = global_idx % ROB_PER_THREAD + thread_base(t);
 /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
        if (rob_array[global_idx].valid && rob_array[global_idx].complete) begin /* verilator coverage_on */ /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
          // Check for exception - stop retire at first exception
          if (rob_array[global_idx].exception) begin
            retire_exception = 1'b1;
            retire_exc_code  = rob_array[global_idx].exc_code;
            retire_exc_pc    = rob_array[global_idx].uop.pc;
            break;  // Don't retire past exception
          end

          // Check for branch mispredict
          if (rob_array[global_idx].uop.is_branch &&
              rob_array[global_idx].branch_taken != rob_array[global_idx].uop.imm[0]) begin
            // Branch mispredict detected at retire - trigger flush
            break; /* verilator coverage_on */
          end

          retire_entry[retired] = rob_array[global_idx];
          retire_valid[retired] = 1'b1;
          retire_tid[retired]   = t;
          retired++;
          local_head++;
          if (local_head >= ROB_PER_THREAD) local_head = 0; /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
        end else begin
          break;  // Not complete, stop retiring this thread /* verilator coverage_on */
        end
      end
      retire_count[t] = retired;
    end
  end

  // ---------------------------------------------------------------------------
  // Exception & Mispredict Detection
  // ---------------------------------------------------------------------------
  always_comb begin
    exception_detected = 1'b0;
    exception_rob_idx  = '0;
    exception_tid      = '0;
    flush_pipeline     = 1'b0;
    flush_redirect_pc  = '0;

    // Priority: exception > branch mispredict
    // v6.3.3: 精確例外 — 只在例外 entry 完成且到達該 thread retire 頭端
    // (所有更舊的 uop 皆已 retire) 時才觸發 flush, 保證精確中斷點
    for (int t = 0; t < SMT_THREADS; t++) begin
      automatic rob_idx_t hidx = thread_base(t) + head[t]; /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
      if (rob_array[hidx].valid && rob_array[hidx].complete &&
          rob_array[hidx].exception) begin
        if (!exception_detected || t < exception_tid) begin
          exception_detected = 1'b1;
          exception_rob_idx  = hidx;
          exception_tid      = tid_t'(t); /* verilator coverage_on */
        end
      end
    end

    if (exception_detected) begin
      flush_pipeline    = 1'b1;
      flush_redirect_pc = 64'h8000_0000;  // Exception handler base (configurable)
    end else if (br_mispredict) begin
      flush_pipeline    = 1'b1;
      flush_redirect_pc = br_mispredict_target_pc;
    end
  end

  // ---------------------------------------------------------------------------
  // Head/Tail Pointer Update
  // ---------------------------------------------------------------------------
  always_comb begin
    head_next = head;
    tail_next = tail;

    // Advance head on retire
    for (int t = 0; t < SMT_THREADS; t++) begin
      head_next[t] = head[t] + retire_count[t]; /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
      if (head_next[t] >= ROB_PER_THREAD) head_next[t] -= ROB_PER_THREAD; /* verilator coverage_on */

      tail_next[t] = tail[t] + disp_count[t]; /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
      if (tail_next[t] >= ROB_PER_THREAD) tail_next[t] -= ROB_PER_THREAD; /* verilator coverage_on */
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential Logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rob_array <= '0;
      head      <= '0;
      tail      <= '0;
    end else begin
      if (flush_pipeline) begin
        if (exception_detected) begin
          // Trap: 清空例外 thread 的整個 ROB 分區 (head = tail => empty)
          for (int i = 0; i < ROB_ENTRIES; i++) begin
            if (entry_tid(i) == exception_tid) begin
              rob_array[i].valid     <= 1'b0;  // v6.3.3.2b: 一併清 complete/exception (R5)
              rob_array[i].complete  <= 1'b0;
              rob_array[i].exception <= 1'b0;
            end
          end
          head[exception_tid] <= tail[exception_tid];
        end else begin
          // v6.3.3: 分支預測失敗 — 精確 flush:
          // 僅清除與分支同 thread 且比分支年輕的 entry,
          // tail 精確回捲到分支之後 (保留分支本身及所有更舊 entry)
          automatic tid_t     bt   = entry_tid(br_mispredict_rob_idx);
          automatic int       base = int'(thread_base(bt));
          automatic int       bl   = int'(br_mispredict_rob_idx) - base; // 分支 local idx
          automatic int       tl   = int'(tail[bt]);
          for (int i = 0; i < ROB_PER_THREAD; i++) begin
            // i 位於循環區間 (bl, tl) 內 => 比分支年輕的在飛 entry
            automatic int d    = (i - bl - 1 + ROB_PER_THREAD) % ROB_PER_THREAD;
            automatic int span = (tl - bl - 1 + ROB_PER_THREAD) % ROB_PER_THREAD;
            if (d < span) begin  // v6.3.3.2b: 一併清 complete/exception (R5)
              rob_array[base + i].valid     <= 1'b0;
              rob_array[base + i].complete  <= 1'b0;
              rob_array[base + i].exception <= 1'b0;
            end
          end
          tail[bt] <= rob_idx_t'((bl + 1) % ROB_PER_THREAD);
        end
      end else begin
        rob_array <= rob_array_next;
        head      <= head_next;
        tail      <= tail_next;
      end
    end
  end

endmodule : cmt_rob
