// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 UVM CPU Tile Tests
// File: tb/cpu_tile_tb/orca_cpu_test.sv
// Description: Various test classes for CPU Tile verification
//=============================================================================

`ifndef ORCA_CPU_TEST_SV
`define ORCA_CPU_TEST_SV

// ---------------------------------------------------------------------------
// Base Test
// ---------------------------------------------------------------------------
class orca_cpu_base_test extends uvm_test;
  `uvm_component_utils(orca_cpu_base_test)

  orca_cpu_env env;
  orca_tb_config cfg;
  virtual orca_cpu_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Create and configure TB config
    cfg = new();
    cfg.num_transactions = 1000;
    cfg.enable_coverage  = 1;
    uvm_config_db#(orca_tb_config)::set(this, "*", "cfg", cfg);

    // Get virtual interface
    if (!uvm_config_db#(virtual orca_cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
    uvm_config_db#(virtual orca_cpu_if)::set(this, "*", "vif", vif);

    // Create environment
    env = orca_cpu_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  function void report_phase(uvm_phase phase);
    uvm_report_server server;
    int err_count;
    super.report_phase(phase);
    server = uvm_report_server::get_server();
    err_count = server.get_severity_count(UVM_ERROR);
    if (err_count == 0)
      `uvm_info("TEST", "
*** TEST PASSED ***
", UVM_NONE)
    else
      `uvm_error("TEST", $sformatf("
*** TEST FAILED with %0d errors ***
", err_count))
  endfunction
endclass : orca_cpu_base_test

// ---------------------------------------------------------------------------
// ALU Random Test
// ---------------------------------------------------------------------------
class orca_cpu_alu_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_alu_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.num_transactions = 5000;
    uvm_config_db#(orca_tb_config)::set(this, "*", "cfg", cfg);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_alu_sequence seq;
    phase.raise_objection(this, "Starting ALU test");
    seq = orca_cpu_alu_sequence::type_id::create("seq");
    seq.start(env.cpu_agent.sequencer);
    phase.drop_objection(this, "Finished ALU test");
  endtask
endclass : orca_cpu_alu_test

// ---------------------------------------------------------------------------
// SMT Stress Test
// ---------------------------------------------------------------------------
class orca_cpu_smt_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_smt_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.num_transactions = 10000;
    uvm_config_db#(orca_tb_config)::set(this, "*", "cfg", cfg);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_smt_sequence seq;
    phase.raise_objection(this, "Starting SMT test");
    seq = orca_cpu_smt_sequence::type_id::create("seq");
    seq.start(env.cpu_agent.sequencer);
    phase.drop_objection(this, "Finished SMT test");
  endtask
endclass : orca_cpu_smt_test

// ---------------------------------------------------------------------------
// Exception Handling Test
// ---------------------------------------------------------------------------
class orca_cpu_exception_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_exception_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_exception_sequence seq;
    phase.raise_objection(this, "Starting exception test");
    seq = orca_cpu_exception_sequence::type_id::create("seq");
    seq.start(env.cpu_agent.sequencer);
    phase.drop_objection(this, "Finished exception test");
  endtask
endclass : orca_cpu_exception_test

// ---------------------------------------------------------------------------
// v6.3.3: ROB Flush / Freelist Recovery Test
// UVM_TESTNAME 用法: ./simv +UVM_TESTNAME=orca_cpu_flush_test
//   (配合 scripts/run_regression.sh, seed 見 TESTS 陣列)
// ---------------------------------------------------------------------------
class orca_cpu_flush_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_flush_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.num_transactions = 2000;   // ~125 flush rounds
    uvm_config_db#(orca_tb_config)::set(this, "*", "cfg", cfg);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_flush_seq seq;
    phase.raise_objection(this, "Starting flush test");
    seq = orca_cpu_flush_seq::type_id::create("seq");
    seq.start(env.cpu_agent.sequencer);
    phase.drop_objection(this, "Finished flush test");
  endtask
endclass : orca_cpu_flush_test

// ---------------------------------------------------------------------------
// v6.3.3: LSU x4 Lane Stress Test
// UVM_TESTNAME 用法: ./simv +UVM_TESTNAME=orca_cpu_lsu_stress_test
// ---------------------------------------------------------------------------
class orca_cpu_lsu_stress_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_lsu_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.num_transactions = 8000;   // 2000 LD/ST per thread
    uvm_config_db#(orca_tb_config)::set(this, "*", "cfg", cfg);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_lsu_stress_seq seq;
    phase.raise_objection(this, "Starting LSU stress test");
    seq = orca_cpu_lsu_stress_seq::type_id::create("seq");
    seq.start(env.cpu_agent.sequencer);
    phase.drop_objection(this, "Finished LSU stress test");
  endtask
endclass : orca_cpu_lsu_stress_test

// ---------------------------------------------------------------------------
// v6.3.3: MUL/VEC/CRYPTO Operand Path Test
// UVM_TESTNAME 用法: ./simv +UVM_TESTNAME=orca_cpu_mul_vec_test
// ---------------------------------------------------------------------------
class orca_cpu_mul_vec_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_mul_vec_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.num_transactions = 4000;
    uvm_config_db#(orca_tb_config)::set(this, "*", "cfg", cfg);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_mul_vec_seq seq;
    phase.raise_objection(this, "Starting MUL/VEC test");
    seq = orca_cpu_mul_vec_seq::type_id::create("seq");
    seq.start(env.cpu_agent.sequencer);
    phase.drop_objection(this, "Finished MUL/VEC test");
  endtask
endclass : orca_cpu_mul_vec_test

// ---------------------------------------------------------------------------
// AIX Co-simulation Test
// ---------------------------------------------------------------------------
class orca_cpu_aix_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_aix_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    orca_aix_sequence seq;
    phase.raise_objection(this, "Starting AIX test");
    seq = orca_aix_sequence::type_id::create("seq");
    // AIX sequence would connect to a different sequencer in real implementation
    // seq.start(env.aix_agent.sequencer);
    phase.drop_objection(this, "Finished AIX test");
  endtask
endclass : orca_cpu_aix_test

// ---------------------------------------------------------------------------
// Regression Test Suite
// ---------------------------------------------------------------------------
class orca_cpu_regression_test extends orca_cpu_base_test;
  `uvm_component_utils(orca_cpu_regression_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_alu_sequence       alu_seq;
    orca_cpu_smt_sequence       smt_seq;
    orca_cpu_exception_sequence exc_seq;

    phase.raise_objection(this, "Starting regression suite");

    `uvm_info("REGRESSION", "Phase 1: ALU random test", UVM_MEDIUM)
    alu_seq = orca_cpu_alu_sequence::type_id::create("alu_seq");
    alu_seq.start(env.cpu_agent.sequencer);

    `uvm_info("REGRESSION", "Phase 2: SMT stress test", UVM_MEDIUM)
    smt_seq = orca_cpu_smt_sequence::type_id::create("smt_seq");
    smt_seq.start(env.cpu_agent.sequencer);

    `uvm_info("REGRESSION", "Phase 3: Exception handling test", UVM_MEDIUM)
    exc_seq = orca_cpu_exception_sequence::type_id::create("exc_seq");
    exc_seq.start(env.cpu_agent.sequencer);

    phase.drop_objection(this, "Finished regression suite");
  endtask
endclass : orca_cpu_regression_test

`endif // ORCA_CPU_TEST_SV
