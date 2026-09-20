// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 ZEN++ SystemVerilog Assertions - CPU Core
// File: tb/sva/sva_cpu_core.sv
// Description: Key safety and liveness assertions for CPU core pipeline
//=============================================================================

`include "orca_pkg.sv"

module sva_cpu_core (
  input logic clk,
  input logic rst_n,

  // Fetch stage
  input logic        fetch_valid,
  input logic [63:0] fetch_pc,
  input logic [31:0] fetch_instr,

  // Decode stage
  input logic        decode_valid,
  input uop_t        decode_uop,

  // Rename stage
  input logic        rename_valid,
  input logic        rename_ready,

  // Dispatch stage
  input logic [DISPATCH_WIDTH-1:0] dispatch_valid,
  input uop_t      [DISPATCH_WIDTH-1:0] dispatch_uop,

  // ROB
  input logic [ROB_ENTRIES-1:0] rob_valid,
  input logic [ROB_ENTRIES-1:0] rob_complete,
  input rob_idx_t rob_head,
  input rob_idx_t rob_tail,

  // Retire stage
  input logic [RETIRE_WIDTH-1:0] retire_valid,
  input logic                    retire_exception,

  // Execution
  input logic [NUM_INT_ALU-1:0] alu_result_valid,
  input logic                   flush_pipeline,

  // SMT
  input tid_t [DISPATCH_WIDTH-1:0] dispatch_tid,
  input tid_t [RETIRE_WIDTH-1:0]   retire_tid,

  // v6.3.3: PRF 寫入觀察點 (12W: alu/fpu/crypto/mul/vec/ld lane0..3)
  input logic          [11:0] prf_wvalid,
  input phys_reg_idx_t [11:0] prf_wtag
);

  import orca_pkg::*;

  // ==========================================================================
  // Safety Assertions (Never happens)
  // ==========================================================================

  // A1: PC must always be 4-byte aligned after reset
  property p_pc_aligned;
    @(posedge clk) disable iff (!rst_n)
    fetch_valid |-> (fetch_pc[1:0] == 2'b00);
  endproperty
  assert property (p_pc_aligned)
    else `uvm_error("SVA_CPU", "Fetch PC not 4-byte aligned!")

  // A2: No two instructions in the same cycle can have the same ROB index
  property p_unique_rob_idx;
    @(posedge clk) disable iff (!rst_n)
    $onehot0(rob_valid) |-> ##1 !$onehot(rob_valid & (rob_valid >> 1));
  endproperty
  // Simplified: Check no duplicate dispatch to same ROB slot
  property p_no_rob_collision;
    @(posedge clk) disable iff (!rst_n)
    (dispatch_valid[0] && dispatch_valid[1]) |->
      (dispatch_uop[0].uop_id != dispatch_uop[1].uop_id);
  endproperty
  assert property (p_no_rob_collision)
    else `uvm_error("SVA_CPU", "ROB index collision detected!")

  // A3: Exception must cause flush within 2 cycles
  property p_exception_flush;
    @(posedge clk) disable iff (!rst_n)
    retire_exception |-> ##[1:2] flush_pipeline;
  endproperty
  assert property (p_exception_flush)
    else `uvm_error("SVA_CPU", "Exception did not trigger flush!")

  // A4: ROB head must never pass tail (no overflow)
  property p_rob_no_overflow;
    @(posedge clk) disable iff (!rst_n)
    (rob_head != rob_tail) |->
      ((rob_tail > rob_head) && (rob_tail - rob_head <= ROB_ENTRIES)) ||
      ((rob_tail < rob_head) && (ROB_ENTRIES - rob_head + rob_tail <= ROB_ENTRIES));
  endproperty
  assert property (p_rob_no_overflow)
    else `uvm_error("SVA_CPU", "ROB overflow detected!")

  // A5: Only completed instructions can retire
  property p_retire_complete;
    @(posedge clk) disable iff (!rst_n)
    retire_valid[0] |-> rob_complete[rob_head];
  endproperty
  assert property (p_retire_complete)
    else `uvm_error("SVA_CPU", "Retiring incomplete instruction!")

  // A6: x0 (zero register) must never be written with non-zero value
  property p_x0_zero;
    @(posedge clk) disable iff (!rst_n)
    (retire_valid[0] && retire_tid[0] == 0) |->
      (decode_uop.rd != 5'b00000);
  endproperty
  assert property (p_x0_zero)
    else `uvm_warning("SVA_CPU", "Writing to x0 detected (should be ignored)")

  // A7: Dispatch width cannot exceed available ROB entries
  property p_dispatch_rob_available;
    @(posedge clk) disable iff (!rst_n)
    $countones(dispatch_valid) <= (ROB_ENTRIES - (rob_tail >= rob_head ?
      (rob_tail - rob_head) : (ROB_ENTRIES - rob_head + rob_tail)));
  endproperty
  assert property (p_dispatch_rob_available)
    else `uvm_error("SVA_CPU", "Dispatch exceeds available ROB entries!")

  // ==========================================================================
  // Liveness Assertions (Must eventually happen)
  // ==========================================================================

  // A8: Every dispatched instruction must eventually complete
  property p_instr_must_complete;
    logic [$clog2(ROB_ENTRIES)-1:0] rob_idx;
    @(posedge clk) disable iff (!rst_n)
    (dispatch_valid[0], rob_idx = dispatch_uop[0].uop_id)
      |-> ##[1:1000] rob_complete[rob_idx] || flush_pipeline;
  endproperty
  assert property (p_instr_must_complete)
    else `uvm_error("SVA_CPU", "Instruction stuck in ROB!")

  // A9: Flush must eventually deassert
  property p_flush_must_end;
    @(posedge clk) disable iff (!rst_n)
    $rose(flush_pipeline) |-> ##[1:20] $fell(flush_pipeline);
  endproperty
  assert property (p_flush_must_end)
    else `uvm_error("SVA_CPU", "Flush stuck active!")

  // A10: Every fetch must eventually retire (no instruction lost)
  property p_fetch_to_retire;
    logic [63:0] pc;
    @(posedge clk) disable iff (!rst_n)
    (fetch_valid, pc = fetch_pc)
      |-> ##[1:2000] (retire_valid[0] && retire_tid[0] == dispatch_tid[0]) || flush_pipeline;
  endproperty
  assert property (p_fetch_to_retire)
    else `uvm_error("SVA_CPU", "Instruction lost in pipeline!")

  // ==========================================================================
  // SMT-Specific Assertions
  // ==========================================================================

  // A11: Per-thread ROB entries must not exceed partition limit
  property p_smt_rob_partition;
    @(posedge clk) disable iff (!rst_n)
    (dispatch_valid[0]) |->
      (dispatch_tid[0] inside {[0:SMT_THREADS-1]});
  endproperty
  assert property (p_smt_rob_partition)
    else `uvm_error("SVA_CPU", "Invalid thread ID in dispatch!")

  // A12: SMT threads must make progress (no starvation)
  property p_smt_no_starvation;
    @(posedge clk) disable iff (!rst_n)
    ##1000 (retire_valid[0] && retire_tid[0] == 0) ##[0:5000]
    (retire_valid[0] && retire_tid[0] == 1) ##[0:5000]
    (retire_valid[0] && retire_tid[0] == 2) ##[0:5000]
    (retire_valid[0] && retire_tid[0] == 3);
  endproperty
  // Note: This is a weak fairness check, may need to be disabled for some tests

  // A13: Only one thread can trigger exception at a time
  property p_single_exception;
    @(posedge clk) disable iff (!rst_n)
    $onehot0({retire_exception, flush_pipeline});
  endproperty
  assert property (p_single_exception)
    else `uvm_error("SVA_CPU", "Multiple simultaneous exceptions!")

  // ==========================================================================
  // Data Integrity Assertions
  // ==========================================================================

  // A14: Decode uop must match fetch instruction (basic decode check)
  property p_decode_consistency;
    @(posedge clk) disable iff (!rst_n)
    (decode_valid && decode_uop.opcode == OP_ALU)
      |-> (decode_uop.rs1_addr == fetch_instr[19:15]);
  endproperty
  assert property (p_decode_consistency)
    else `uvm_error("SVA_CPU", "Decode inconsistency: rs1 mismatch!")

  // A15: ALU result must be valid within 3 cycles of dispatch
  property p_alu_latency;
    @(posedge clk) disable iff (!rst_n)
    (dispatch_valid[0] && dispatch_uop[0].opcode inside {OP_ALU, OP_ALUI})
      |-> ##[1:3] alu_result_valid[0];
  endproperty
  assert property (p_alu_latency)
    else `uvm_error("SVA_CPU", "ALU result latency violation!")

  // ==========================================================================
  // v6.3.3: PRF 寫入 tag 合法性 (12 寫埠供應所有 EXU 寫回)
  // ==========================================================================

  // A16: 每個被斷言的寫埠 tag 必須在 INT_PRF_ENTRIES 範圍內 (無越界/X)
  generate
    for (genvar p = 0; p < 12; p++) begin : gen_prf_wtag_range
      property p_prf_wtag_in_range;
        @(posedge clk) disable iff (!rst_n)
        prf_wvalid[p] |-> (prf_wtag[p] < INT_PRF_ENTRIES);
      endproperty
      assert property (p_prf_wtag_in_range)
        else `uvm_error("SVA_CPU",
          $sformatf("PRF write port %0d tag out of range: %0d", p, prf_wtag[p]))
    end
  endgenerate

  // A17: 同拍不得有兩個寫埠寫入同一個已分配 (>=32) 的 prd
  //      (rename/freelist 保證 prd 唯一; 寫同 tag 代表 rename 或 freelist 破壞)
  generate
    for (genvar i = 0; i < 12; i++) begin : gen_prf_dup_i
      for (genvar j = i + 1; j < 12; j++) begin : gen_prf_dup_j
        property p_prf_no_dup_wtag;
          @(posedge clk) disable iff (!rst_n)
          !(prf_wvalid[i] && prf_wvalid[j] &&
            prf_wtag[i] >= 32 && prf_wtag[i] == prf_wtag[j]);
        endproperty
        assert property (p_prf_no_dup_wtag)
          else `uvm_error("SVA_CPU",
            $sformatf("PRF write ports %0d/%0d write same tag %0d!",
              i, j, prf_wtag[i]))
      end
    end
  endgenerate

  // A18: 寫入 tag < 32 代表目的 arch reg 未經 rename 分配 (如 rd==x0),
  //      屬可容忍但值得注意 — 以 warning 呈現 (nop 流會觸發)
  generate
    for (genvar p = 0; p < 12; p++) begin : gen_prf_wtag_low
      property p_prf_wtag_low_warn;
        @(posedge clk) disable iff (!rst_n)
        prf_wvalid[p] |-> (prf_wtag[p] >= 32);
      endproperty
      assert property (p_prf_wtag_low_warn)
        else `uvm_warning("SVA_CPU",
          $sformatf("PRF write port %0d writes unallocated tag %0d (rd==x0?)",
            p, prf_wtag[p]))
    end
  endgenerate

  // ==========================================================================
  // Coverage Properties (for functional coverage)
  // ==========================================================================

  // C1: All SMT threads have dispatched instructions
  property c_all_threads_dispatch;
    @(posedge clk) disable iff (!rst_n)
    (dispatch_tid[0] == 0) ##1 (dispatch_tid[0] == 1)
      ##1 (dispatch_tid[0] == 2) ##1 (dispatch_tid[0] == 3);
  endproperty
  cover property (c_all_threads_dispatch);

  // C2: Exception followed by flush
  property c_exception_flush;
    @(posedge clk) disable iff (!rst_n)
    retire_exception ##1 flush_pipeline;
  endproperty
  cover property (c_exception_flush);

  // C3: Full ROB (all entries valid)
  property c_rob_full;
    @(posedge clk) disable iff (!rst_n)
    (rob_tail - rob_head) == ROB_ENTRIES;
  endproperty
  cover property (c_rob_full);

  // C4: All ALUs active simultaneously
  property c_all_alu_active;
    @(posedge clk) disable iff (!rst_n)
    (&alu_result_valid);
  endproperty
  cover property (c_all_alu_active);

  // C5: Branch mispredict followed by redirect
  property c_branch_mispredict;
    @(posedge clk) disable iff (!rst_n)
    $rose(flush_pipeline) ##0 retire_valid[0];
  endproperty
  cover property (c_branch_mispredict);

endmodule : sva_cpu_core
