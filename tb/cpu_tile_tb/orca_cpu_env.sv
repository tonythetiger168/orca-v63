// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 UVM CPU Tile Environment
// File: tb/cpu_tile_tb/orca_cpu_env.sv
// Description: Environment with agent, reference model, and scoreboard
//=============================================================================

`ifndef ORCA_CPU_ENV_SV
`define ORCA_CPU_ENV_SV

class orca_cpu_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(orca_cpu_scoreboard)

  uvm_analysis_export #(orca_cpu_transaction) expected_analysis_export;
  uvm_analysis_export #(orca_cpu_transaction) actual_analysis_export;

  uvm_tlm_analysis_fifo #(orca_cpu_transaction) expected_fifo;
  uvm_tlm_analysis_fifo #(orca_cpu_transaction) actual_fifo;

  int match_count;
  int mismatch_count;
  int total_transactions;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    match_count = 0;
    mismatch_count = 0;
    total_transactions = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_analysis_export = new("expected_analysis_export", this);
    actual_analysis_export   = new("actual_analysis_export", this);
    expected_fifo = new("expected_fifo", this);
    actual_fifo   = new("actual_fifo", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    expected_analysis_export.connect(expected_fifo.analysis_export);
    actual_analysis_export.connect(actual_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_transaction expected_tr;
    orca_cpu_transaction actual_tr;
    forever begin
      expected_fifo.get(expected_tr);
      actual_fifo.get(actual_tr);

      total_transactions++;

      if (expected_tr.compare(actual_tr)) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("MATCH #%0d: %s", total_transactions,
          expected_tr.convert2string()), UVM_HIGH)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("MISMATCH #%0d:
  Expected: PC=%h RES=%h EXC=%b
  Actual:   PC=%h RES=%h EXC=%b",
          total_transactions,
          expected_tr.pc, expected_tr.expected_result, expected_tr.expected_exception,
          actual_tr.pc, actual_tr.actual_result, actual_tr.actual_exception))
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCOREBOARD", $sformatf("
========================================
" +
      "Scoreboard Summary:
" +
      "  Total Transactions: %0d
" +
      "  Matches:          %0d
" +
      "  Mismatches:       %0d
" +
      "  Match Rate:       %0.2f%%
" +
      "========================================",
      total_transactions, match_count, mismatch_count,
      (total_transactions > 0) ? (100.0 * match_count / total_transactions) : 0), UVM_LOW)
  endfunction
endclass : orca_cpu_scoreboard

// ---------------------------------------------------------------------------
// Coverage Collector
// ---------------------------------------------------------------------------
class orca_cpu_coverage extends uvm_subscriber #(orca_cpu_transaction);
  `uvm_component_utils(orca_cpu_coverage)

  covergroup cpu_cg;
    option.per_instance = 1;

    cp_opcode: coverpoint tr.op_type {
      bins alu_ops    = {OP_ALU, OP_ALUI};
      bins load_ops   = {OP_LOAD};
      bins store_ops  = {OP_STORE};
      bins branch_ops = {OP_BRANCH, OP_JAL, OP_JALR};
      bins fp_ops     = {OP_FP};
      bins vec_ops    = {OP_VEC, OP_VEC_CFG};
      bins aix_ops    = {OP_AIX};
      bins other_ops  = default;
    }

    cp_thread: coverpoint tr.thread_id {
      bins tid[] = {[0:3]};
    }

    cp_rs1: coverpoint tr.rs1_addr {
      bins regs[] = {[0:31]};
    }

    cp_rd: coverpoint tr.rd_addr {
      bins regs[] = {[0:31]};
      bins x0_write = {0};
    }

    cross_opcode_thread: cross cp_opcode, cp_thread;
  endgroup : cpu_cg

  orca_cpu_transaction tr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cpu_cg = new();
  endfunction

  function void write(orca_cpu_transaction t);
    tr = t;
    cpu_cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COVERAGE", $sformatf("CPU Coverage: %0.2f%%", cpu_cg.get_coverage()), UVM_LOW)
  endfunction
endclass : orca_cpu_coverage

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class orca_cpu_env extends uvm_env;
  `uvm_component_utils(orca_cpu_env)

  orca_cpu_agent       cpu_agent;
  orca_ref_model       ref_model;
  orca_cpu_scoreboard  scoreboard;
  orca_cpu_coverage    coverage;
  orca_tb_config       cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get configuration
    if (!uvm_config_db#(orca_tb_config)::get(this, "", "cfg", cfg)) begin
      cfg = new();
      `uvm_info("ENV", "Using default TB config", UVM_MEDIUM)
    end

    // Create components
    cpu_agent   = orca_cpu_agent::type_id::create("cpu_agent", this);
    ref_model   = orca_ref_model::type_id::create("ref_model", this);
    scoreboard  = orca_cpu_scoreboard::type_id::create("scoreboard", this);
    coverage    = orca_cpu_coverage::type_id::create("coverage", this);

    // Set agent to active
    uvm_config_db#(uvm_active_passive_enum)::set(this, "cpu_agent", "is_active", UVM_ACTIVE);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect monitor to reference model and scoreboard
    cpu_agent.monitor.analysis_port.connect(ref_model.analysis_imp);
    cpu_agent.monitor.analysis_port.connect(scoreboard.actual_analysis_export);
    cpu_agent.monitor.analysis_port.connect(coverage.analysis_export);
    // Reference model output would connect to scoreboard expected (simplified)
  endfunction
endclass : orca_cpu_env

`endif // ORCA_CPU_ENV_SV
