// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 ZEN++ SystemVerilog Assertions - Reorder Buffer (ROB)
// File: tb/sva/sva_rob.sv
// Description: ROB-specific safety, liveness, and data integrity assertions
//=============================================================================

`include "orca_pkg.sv"

module sva_rob (
  input logic clk,
  input logic rst_n,

  // ROB state
  input rob_entry_t [ROB_ENTRIES-1:0] rob_array,
  input logic       [ROB_ENTRIES-1:0] rob_valid,
  input logic       [ROB_ENTRIES-1:0] rob_complete,
  input logic       [ROB_ENTRIES-1:0] rob_exception,
  input rob_idx_t   [SMT_THREADS-1:0] head,
  input rob_idx_t   [SMT_THREADS-1:0] tail,
  input logic       [SMT_THREADS-1:0] rob_full,
  input logic       [SMT_THREADS-1:0] rob_empty,

  // Dispatch
  input logic [DISPATCH_WIDTH-1:0] disp_valid,
  input uop_t [DISPATCH_WIDTH-1:0] disp_uop,

  // Retire
  input logic [RETIRE_WIDTH-1:0] retire_valid,
  input rob_entry_t [RETIRE_WIDTH-1:0] retire_entry,

  // Flush
  input logic flush_valid,
  input tid_t flush_tid,

  // Exception
  input logic     exception_detected,
  input rob_idx_t exception_rob_idx,
  input tid_t     exception_tid,

  // v6.3.3: 精確 flush / freelist 恢復觀察點 (新增, 供 R18~R21 使用)
  input logic        br_mispredict,
  input rob_idx_t    br_mispredict_rob_idx,
  input logic [15:0] fl_free_cnt,      // rnu_freelist 目前空閒 prd 數 (cnt)
  input logic        fl_empty
);

  import orca_pkg::*;

  localparam int ROB_PER_THREAD = ROB_ENTRIES / SMT_THREADS;

  // ==========================================================================
  // Pointer Safety
  // ==========================================================================

  // R1: Head pointer must be within thread's partition
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_head_range
      property p_head_in_range;
        @(posedge clk) disable iff (!rst_n)
        (head[t] >= t * ROB_PER_THREAD) && (head[t] < (t + 1) * ROB_PER_THREAD);
      endproperty
      assert property (p_head_in_range)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d head pointer out of range: %0d", t, head[t]))
    end
  endgenerate

  // R2: Tail pointer must be within thread's partition
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_tail_range
      property p_tail_in_range;
        @(posedge clk) disable iff (!rst_n)
        (tail[t] >= t * ROB_PER_THREAD) && (tail[t] < (t + 1) * ROB_PER_THREAD);
      endproperty
      assert property (p_tail_in_range)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d tail pointer out of range: %0d", t, tail[t]))
    end
  endgenerate

  // R3: Head must never overtake tail (circular buffer invariant)
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_head_tail_order
      property p_head_not_overtake;
        @(posedge clk) disable iff (!rst_n)
        (!flush_valid) |->
          ((head[t] <= tail[t]) && (tail[t] - head[t] <= ROB_PER_THREAD)) ||
          ((head[t] > tail[t]) && (ROB_PER_THREAD - head[t] + tail[t] <= ROB_PER_THREAD));
      endproperty
      assert property (p_head_not_overtake)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d head overtook tail!", t))
    end
  endgenerate

  // ==========================================================================
  // Valid Bit Consistency
  // ==========================================================================

  // R4: Valid entries must be between head and tail
  generate
    for (genvar i = 0; i < ROB_ENTRIES; i++) begin : gen_valid_range
      int t = i / ROB_PER_THREAD;
      property p_valid_in_range;
        @(posedge clk) disable iff (!rst_n)
        rob_valid[i] |->
          ((head[t] <= tail[t]) && (i >= head[t] && i < tail[t])) ||
          ((head[t] > tail[t]) && (i >= head[t] || i < tail[t]));
      endproperty
      assert property (p_valid_in_range)
        else `uvm_error("SVA_ROB", $sformatf("ROB entry %0d valid but outside head-tail range", i))
    end
  endgenerate

  // R5: Complete implies valid
  property p_complete_implies_valid;
    @(posedge clk) disable iff (!rst_n)
    (rob_complete != '0) |-> ((rob_complete & ~rob_valid) == '0);
  endproperty
  assert property (p_complete_implies_valid)
    else `uvm_error("SVA_ROB", "Complete bit set for invalid ROB entry!")

  // R6: Exception implies complete
  property p_exception_implies_complete;
    @(posedge clk) disable iff (!rst_n)
    (rob_exception != '0) |-> ((rob_exception & ~rob_complete) == '0);
  endproperty
  assert property (p_exception_implies_complete)
    else `uvm_error("SVA_ROB", "Exception bit set for incomplete ROB entry!")

  // ==========================================================================
  // Dispatch Safety
  // ==========================================================================

  // R7: Dispatch to full ROB must be rejected
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_no_dispatch_when_full
      property p_no_dispatch_full;
        @(posedge clk) disable iff (!rst_n)
        rob_full[t] |-> !(disp_valid[0] && disp_uop[0].tid == t);
      endproperty
      assert property (p_no_dispatch_full)
        else `uvm_error("SVA_ROB", $sformatf("Dispatch to full ROB thread %0d!", t))
    end
  endgenerate

  // R8: Dispatched entries must be marked valid next cycle
  property p_dispatch_valid;
    logic [$clog2(ROB_ENTRIES)-1:0] idx;
    @(posedge clk) disable iff (!rst_n)
    (disp_valid[0], idx = disp_uop[0].uop_id) |-> ##1 rob_valid[idx];
  endproperty
  assert property (p_dispatch_valid)
    else `uvm_error("SVA_ROB", "Dispatched entry not marked valid!")

  // R9: Dispatch must set complete to 0
  property p_dispatch_not_complete;
    logic [$clog2(ROB_ENTRIES)-1:0] idx;
    @(posedge clk) disable iff (!rst_n)
    (disp_valid[0], idx = disp_uop[0].uop_id) |-> ##1 !rob_complete[idx];
  endproperty
  assert property (p_dispatch_not_complete)
    else `uvm_error("SVA_ROB", "Dispatched entry already complete!")

  // ==========================================================================
  // Retire Safety
  // ==========================================================================

  // R10: Retire must only happen for valid, complete, non-exception entries
  property p_retire_safe;
    @(posedge clk) disable iff (!rst_n)
    retire_valid[0] |->
      rob_valid[head[retire_entry[0].uop.tid]] &&
      rob_complete[head[retire_entry[0].uop.tid]] &&
      !rob_exception[head[retire_entry[0].uop.tid]];
  endproperty
  assert property (p_retire_safe)
    else `uvm_error("SVA_ROB", "Unsafe retire attempted!")

  // R11: Retire must advance head pointer
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_retire_advances_head
      property p_retire_advances_head;
        @(posedge clk) disable iff (!rst_n)
        (retire_valid[0] && retire_entry[0].uop.tid == t)
          |-> ##1 (head[t] != $past(head[t]) || flush_valid);
      endproperty
      assert property (p_retire_advances_head)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d head not advanced after retire!", t))
    end
  endgenerate

  // R12: Retired entries must be invalidated
  property p_retire_invalidates;
    logic [$clog2(ROB_ENTRIES)-1:0] idx;
    @(posedge clk) disable iff (!rst_n)
    (retire_valid[0], idx = head[retire_entry[0].uop.tid])
      |-> ##1 !rob_valid[idx];
  endproperty
  assert property (p_retire_invalidates)
    else `uvm_error("SVA_ROB", "Retired entry not invalidated!")

  // ==========================================================================
  // Flush Safety
  // ==========================================================================

  // R13: Flush must invalidate all entries for affected thread
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_flush_invalidate
      property p_flush_invalidate;
        @(posedge clk) disable iff (!rst_n)
        (flush_valid && flush_tid == t)
          |-> ##1 (rob_valid[t*ROB_PER_THREAD +: ROB_PER_THREAD] == '0);
      endproperty
      assert property (p_flush_invalidate)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d entries not invalidated after flush!", t))
    end
  endgenerate

  // R14: Flush must reset head to tail
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_flush_reset_head
      property p_flush_reset_head;
        @(posedge clk) disable iff (!rst_n)
        (flush_valid && flush_tid == t) |-> ##1 (head[t] == tail[t]);
      endproperty
      assert property (p_flush_reset_head)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d head not reset after flush!", t))
    end
  endgenerate

  // R15: Exception must be the oldest in ROB
  property p_exception_oldest;
    @(posedge clk) disable iff (!rst_n)
    exception_detected |->
      (exception_rob_idx == head[exception_tid]);
  endproperty
  assert property (p_exception_oldest)
    else `uvm_error("SVA_ROB", "Exception not at head of ROB!")

  // ==========================================================================
  // v6.3.3: Flush 精確性 (例外全清 / mispredict 只清年輕 entry) + freelist 守恆
  // ==========================================================================

  // R18: 例外 flush (retire 頭端精確例外) 後, 該 thread ROB 分區必須全空
  property p_exception_flush_empties_rob;
    @(posedge clk) disable iff (!rst_n)
    (flush_valid && exception_detected) |-> ##1 rob_empty[$past(exception_tid)];
  endproperty
  assert property (p_exception_flush_empties_rob)
    else `uvm_error("SVA_ROB",
      $sformatf("Thread %0d ROB not empty after precise exception flush!", exception_tid))

  // R19: 分支 mispredict 精確 flush — head 不變 (保留分支及更舊 entry),
  //      tail 精確回捲到分支之後 (bl + 1)
  property p_mispredict_precise_rewind;
    rob_idx_t bidx;
    @(posedge clk) disable iff (!rst_n)
    (flush_valid && br_mispredict && !exception_detected, bidx = br_mispredict_rob_idx)
      |-> ##1 (tail[bidx / ROB_PER_THREAD] ==
                 rob_idx_t'(((bidx % ROB_PER_THREAD) + 1) % ROB_PER_THREAD)) &&
              (head[bidx / ROB_PER_THREAD] == $past(head[bidx / ROB_PER_THREAD]));
  endproperty
  assert property (p_mispredict_precise_rewind)
    else `uvm_error("SVA_ROB", "Mispredict flush did not precisely rewind tail!")

  // R20: flush 時 freelist 全量重建 — 空閒數不得低於 flush 前
  //      (被清掉的年輕 uop 所持有的 prd 必須回收), 且不得超過 pool 總量
  property p_freelist_flush_recover;
    @(posedge clk) disable iff (!rst_n)
    flush_valid |-> ##1 (fl_free_cnt >= $past(fl_free_cnt)) &&
                        (fl_free_cnt <= (INT_PRF_ENTRIES - 32));
  endproperty
  assert property (p_freelist_flush_recover)
    else `uvm_error("SVA_ROB",
      $sformatf("Freelist not recovered after flush: cnt %0d -> %0d",
        $past(fl_free_cnt), fl_free_cnt))

  // R21: freelist 數量守恆 — 任何時候空閒數不得超過 pool 容量,
  //      且 freelist 空時不得再有 dispatch (上游 rename 應 stall)
  property p_freelist_count_bounded;
    @(posedge clk) disable iff (!rst_n)
    fl_free_cnt <= (INT_PRF_ENTRIES - 32);
  endproperty
  assert property (p_freelist_count_bounded)
    else `uvm_error("SVA_ROB",
      $sformatf("Freelist count out of bounds: %0d", fl_free_cnt))

  property p_no_dispatch_when_freelist_empty;
    @(posedge clk) disable iff (!rst_n)
    fl_empty |-> !(|disp_valid);
  endproperty
  assert property (p_no_dispatch_when_freelist_empty)
    else `uvm_error("SVA_ROB", "Dispatch while freelist empty!")

  // ==========================================================================
  // Liveness
  // ==========================================================================

  // R16: Empty ROB must eventually accept dispatch
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_empty_accept_dispatch
      property p_empty_accept_dispatch;
        @(posedge clk) disable iff (!rst_n)
        rob_empty[t] |-> ##[1:10] !rob_empty[t];
      endproperty
      assert property (p_empty_accept_dispatch)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d ROB stuck empty!", t))
    end
  endgenerate

  // R17: Full ROB must eventually retire
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_full_eventually_retire
      property p_full_retire;
        @(posedge clk) disable iff (!rst_n)
        rob_full[t] |-> ##[1:100] !rob_full[t];
      endproperty
      assert property (p_full_retire)
        else `uvm_error("SVA_ROB", $sformatf("Thread %0d ROB stuck full!", t))
    end
  endgenerate

  // ==========================================================================
  // Coverage
  // ==========================================================================

  // C1: All threads have full ROB
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_cover_full
      property c_rob_full_thread;
        @(posedge clk) disable iff (!rst_n)
        rob_full[t];
      endproperty
      cover property (c_rob_full_thread);
    end
  endgenerate

  // C2: All threads have empty ROB
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_cover_empty
      property c_rob_empty_thread;
        @(posedge clk) disable iff (!rst_n)
        rob_empty[t];
      endproperty
      cover property (c_rob_empty_thread);
    end
  endgenerate

  // C3: Exception on each thread
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_cover_exception
      property c_exception_thread;
        @(posedge clk) disable iff (!rst_n)
        exception_detected && exception_tid == t;
      endproperty
      cover property (c_exception_thread);
    end
  endgenerate

  // C4: Flush on each thread
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_cover_flush
      property c_flush_thread;
        @(posedge clk) disable iff (!rst_n)
        flush_valid && flush_tid == t;
      endproperty
      cover property (c_flush_thread);
    end
  endgenerate

  // C5: Maximum retire width (all ports active)
  property c_max_retire;
    @(posedge clk) disable iff (!rst_n)
    (&retire_valid);
  endproperty
  cover property (c_max_retire);

  // C7: v6.3.3 精確 mispredict flush (非例外) 發生
  property c_precise_mispredict_flush;
    @(posedge clk) disable iff (!rst_n)
    flush_valid && br_mispredict && !exception_detected;
  endproperty
  cover property (c_precise_mispredict_flush);

  // C8: v6.3.3 flush 觸發 freelist 全量重建 (空閒數上升)
  property c_freelist_rebuild;
    @(posedge clk) disable iff (!rst_n)
    flush_valid ##1 (fl_free_cnt > $past(fl_free_cnt));
  endproperty
  cover property (c_freelist_rebuild);

  // C6: Wrap-around (head > tail in circular buffer)
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_cover_wraparound
      property c_wraparound;
        @(posedge clk) disable iff (!rst_n)
        head[t] > tail[t];
      endproperty
      cover property (c_wraparound);
    end
  endgenerate

endmodule : sva_rob
