// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 UVM Testbench Package
// File: tb/orca_uvm_pkg.sv
// Description: Shared UVM components, transactions, and configuration
//=============================================================================

`ifndef ORCA_UVM_PKG_SV
`define ORCA_UVM_PKG_SV

package orca_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import orca_pkg::*;

  // ---------------------------------------------------------------------------
  // Testbench Configuration
  // ---------------------------------------------------------------------------
  class orca_tb_config extends uvm_object;
    `uvm_object_utils(orca_tb_config)

    int num_cpu_tiles    = 1;    // For unit-level TB, test 1 tile
    int num_ai_tiles     = 0;    // CPU-only test initially
    int num_transactions = 10000;
    int seed             = 42;
    bit enable_coverage  = 1;
    bit enable_wave_dump = 0;

    function new(string name = "orca_tb_config");
      super.new(name);
    endfunction
  endclass : orca_tb_config

  // ---------------------------------------------------------------------------
  // CPU Transaction (Instruction-level)
  // ---------------------------------------------------------------------------
  class orca_cpu_transaction extends uvm_sequence_item;
    `uvm_object_utils(orca_cpu_transaction)

    // Instruction fields
    rand logic [31:0]  instr;
    rand logic [63:0]  pc;
    rand tid_t         thread_id;
    rand logic [63:0]  rs1_data;
    rand logic [63:0]  rs2_data;
    rand logic [4:0]   rd_addr;
    rand logic [4:0]   rs1_addr;
    rand logic [4:0]   rs2_addr;

    // Expected result (from reference model)
    logic [63:0]       expected_result;
    logic              expected_exception;
    exception_t        expected_exc_code;

    // Actual result (from DUT)
    logic [63:0]       actual_result;
    logic              actual_exception;
    exception_t        actual_exc_code;

    // Transaction type
    rand opcode_type_t op_type;

    // Constraints
    constraint valid_pc_c {
      pc[1:0] == 2'b00;  // 4-byte aligned
      pc inside {[64'h8000_0000 : 64'h8000_FFFF]};
    }

    constraint valid_reg_c {
      rd_addr  inside {[0:31]};
      rs1_addr inside {[0:31]};
      rs2_addr inside {[0:31]};
    }

    constraint thread_dist_c {
      thread_id dist {0:=40, 1:=30, 2:=20, 3:=10};
    }

    function new(string name = "orca_cpu_transaction");
      super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
      orca_cpu_transaction rhs_;
      if (!$cast(rhs_, rhs)) begin
        `uvm_fatal("do_copy", "Cast failed")
      end
      super.do_copy(rhs);
      this.instr            = rhs_.instr;
      this.pc               = rhs_.pc;
      this.thread_id        = rhs_.thread_id;
      this.rs1_data         = rhs_.rs1_data;
      this.rs2_data         = rhs_.rs2_data;
      this.rd_addr          = rhs_.rd_addr;
      this.rs1_addr         = rhs_.rs1_addr;
      this.rs2_addr         = rhs_.rs2_addr;
      this.expected_result  = rhs_.expected_result;
      this.expected_exception = rhs_.expected_exception;
      this.expected_exc_code  = rhs_.expected_exc_code;
      this.actual_result    = rhs_.actual_result;
      this.actual_exception = rhs_.actual_exception;
      this.actual_exc_code  = rhs_.actual_exc_code;
      this.op_type          = rhs_.op_type;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      orca_cpu_transaction rhs_;
      if (!$cast(rhs_, rhs)) return 0;
      return (super.do_compare(rhs, comparer) &&
              (this.expected_result == rhs_.actual_result) &&
              (this.expected_exception == rhs_.actual_exception) &&
              (this.expected_exc_code == rhs_.actual_exc_code));
    endfunction

    function string convert2string();
      return $sformatf("PC=%h TID=%0d OP=%s INSTR=%h RS1=%h RS2=%h EXP=%h ACT=%h %s",
        pc, thread_id, op_type.name(), instr, rs1_data, rs2_data,
        expected_result, actual_result,
        (expected_result == actual_result) ? "PASS" : "FAIL");
    endfunction
  endclass : orca_cpu_transaction

  // ---------------------------------------------------------------------------
  // AIX Transaction (CPU-AI Interface)
  // ---------------------------------------------------------------------------
  class orca_aix_transaction extends uvm_sequence_item;
    `uvm_object_utils(orca_aix_transaction)

    rand aix_op_t      aix_op;
    rand logic [15:0]  handle;
    rand aix_tdb_t     tdb;
    rand tid_t         src_thread;
    rand logic [2:0]   dst_tile;

    aix_status_t       status;
    logic [63:0]       completion_time;

    function new(string name = "orca_aix_transaction");
      super.new(name);
    endfunction
  endclass : orca_aix_transaction

  // ---------------------------------------------------------------------------
  // Scoreboard Reference Model
  // ---------------------------------------------------------------------------
  class orca_ref_model extends uvm_component;
    `uvm_component_utils(orca_ref_model)

    // Architectural state (per thread)
    logic [63:0] xreg [SMT_THREADS][32];
    logic [63:0] pc   [SMT_THREADS];

    uvm_analysis_imp #(orca_cpu_transaction, orca_ref_model) analysis_imp;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_imp = new("analysis_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // Initialize architectural state
      for (int t = 0; t < SMT_THREADS; t++) begin
        pc[t] = 64'h8000_0000;
        for (int r = 0; r < 32; r++) begin
          xreg[t][r] = '0;
        end
      end
    endfunction

    function void write(orca_cpu_transaction tr);
      // Execute instruction in reference model
      logic [63:0] result;
      logic exc;
      exception_t exc_code;

      // Decode and execute
      case (tr.op_type)
        OP_ALU, OP_ALUI: begin
          result = execute_alu(tr.instr, tr.rs1_data, tr.rs2_data);
          exc = 1'b0;
          exc_code = `EXC_NONE;
        end
        OP_LOAD: begin
          result = tr.rs1_data + {{52{tr.instr[31]}}, tr.instr[31:20]};
          exc = 1'b0;
        end
        OP_STORE: begin
          result = '0;
          exc = 1'b0;
        end
        OP_BRANCH: begin
          result = '0;
          exc = 1'b0;
        end
        default: begin
          result = '0;
          exc = 1'b0;
        end
      endcase

      tr.expected_result = result;
      tr.expected_exception = exc;
      tr.expected_exc_code = exc_code;

      // Update PC
      if (tr.op_type == OP_BRANCH) begin
        // Simplified: always not-taken for reference model
        pc[tr.thread_id] = pc[tr.thread_id] + 4;
      end else if (tr.op_type == OP_JAL) begin
        pc[tr.thread_id] = pc[tr.thread_id] + {{43{tr.instr[31]}}, tr.instr[31], tr.instr[19:12], tr.instr[20], tr.instr[30:21], 1'b0};
      end else begin
        pc[tr.thread_id] = pc[tr.thread_id] + 4;
      end

      // Update destination register
      if (tr.rd_addr != 0 && !exc) begin
        xreg[tr.thread_id][tr.rd_addr] = result;
      end
    endfunction

    function logic [63:0] execute_alu(logic [31:0] instr, logic [63:0] a, logic [63:0] b);
      logic [4:0] funct5 = instr[31:27];
      logic [2:0] funct3 = instr[14:12];
      logic [6:0] opcode = instr[6:0];
      logic [63:0] imm_i = {{52{instr[31]}}, instr[31:20]};
      logic [63:0] operand_b = (opcode == 7'b0010011) ? imm_i : b;

      case (funct3)
        3'b000: return (instr[30] && opcode == 7'b0110011) ? (a - operand_b) : (a + operand_b);
        3'b001: return a << operand_b[5:0];
        3'b010: return {63'b0, ($signed(a) < $signed(operand_b))};
        3'b011: return {63'b0, (a < operand_b)};
        3'b100: return a ^ operand_b;
        3'b101: return (instr[30]) ? ($signed(a) >>> operand_b[5:0]) : (a >> operand_b[5:0]);
        3'b110: return a | operand_b;
        3'b111: return a & operand_b;
        default: return '0;
      endcase
    endfunction
  endclass : orca_ref_model

endpackage : orca_uvm_pkg

`endif // ORCA_UVM_PKG_SV
