//=============================================================================
// ORCA v6.3 UVM CPU Tile Agent
// File: tb/cpu_tile_tb/orca_cpu_agent.sv
// Description: Agent with sequencer, driver, and monitor for CPU Tile
//=============================================================================

`ifndef ORCA_CPU_AGENT_SV
`define ORCA_CPU_AGENT_SV

class orca_cpu_sequencer extends uvm_sequencer #(orca_cpu_transaction);
  `uvm_component_utils(orca_cpu_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : orca_cpu_sequencer

// ---------------------------------------------------------------------------
// Driver: Converts transactions to pin-level signals
// ---------------------------------------------------------------------------
class orca_cpu_driver extends uvm_driver #(orca_cpu_transaction);
  `uvm_component_utils(orca_cpu_driver)

  virtual orca_cpu_if vif;
  orca_tb_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual orca_cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
    if (!uvm_config_db#(orca_tb_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "TB config not found")
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_transaction tr;
    forever begin
      seq_item_port.get_next_item(tr);
      drive_transaction(tr);
      seq_item_port.item_done();
    end
  endtask

  task drive_transaction(orca_cpu_transaction tr);
    @(posedge vif.clk);
    vif.fetch_req_valid <= 1'b1;
    vif.fetch_pc        <= tr.pc;
    vif.fetch_tid       <= tr.thread_id;

    // Wait for fetch ready
    while (!vif.fetch_ready) @(posedge vif.clk);

    // Drive instruction into decode pipeline
    @(posedge vif.clk);
    vif.decode_instr    <= tr.instr;
    vif.decode_valid    <= 1'b1;
    vif.decode_tid      <= tr.thread_id;
    vif.decode_rs1_data <= tr.rs1_data;
    vif.decode_rs2_data <= tr.rs2_data;

    @(posedge vif.clk);
    vif.fetch_req_valid <= 1'b0;
    vif.decode_valid    <= 1'b0;

    `uvm_info("DRIVER", $sformatf("Drove: %s", tr.convert2string()), UVM_HIGH)
  endtask
endclass : orca_cpu_driver

// ---------------------------------------------------------------------------
// Monitor: Observes DUT outputs and creates analysis transactions
// ---------------------------------------------------------------------------
class orca_cpu_monitor extends uvm_monitor;
  `uvm_component_utils(orca_cpu_monitor)

  virtual orca_cpu_if vif;
  uvm_analysis_port #(orca_cpu_transaction) analysis_port;

  // ---------------------------------------------------------------------------
  // v6.3.3: Functional Coverage
  //   - opcode 類別 (由 retire instr[6:0] 分類)
  //   - flush 事件 (cmt_rob flush_pipeline)
  //   - LSU lane 使用 (isu_mem 4 lane issue valid)
  // ---------------------------------------------------------------------------
  typedef enum int {
    OC_ALU, OC_LOAD, OC_STORE, OC_BRANCH,
    OC_MUL_DIV, OC_VEC, OC_CRYPTO, OC_OTHER
  } opclass_e;

  opclass_e               cov_opclass;
  logic                   cov_flush;
  logic [NUM_LD_PIPE-1:0] cov_lsu_lane;
  logic [11:0]            cov_prf_wv;

  covergroup cpu_mon_cg;
    option.per_instance = 1;

    cp_opcode_class: coverpoint cov_opclass {
      bins alu    = {OC_ALU};
      bins load   = {OC_LOAD};
      bins store  = {OC_STORE};
      bins branch = {OC_BRANCH};
      bins muldiv = {OC_MUL_DIV};
      bins vec    = {OC_VEC};
      bins crypto = {OC_CRYPTO};
      bins other  = {OC_OTHER};
    }

    cp_flush: coverpoint cov_flush {
      bins no_flush = {0};
      bins flush    = {1};
    }

    cp_lsu_lane: coverpoint cov_lsu_lane {
      bins idle       = {4'b0000};
      bins lane0      = {4'b0001};
      bins lane1      = {4'b0010};
      bins lane2      = {4'b0100};
      bins lane3      = {4'b1000};
      bins two_lanes  = {4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010, 4'b1100};
      bins three_lanes= {4'b0111, 4'b1011, 4'b1101, 4'b1110};
      bins all_four   = {4'b1111};
    }

    cp_prf_wports: coverpoint cov_prf_wv {
      bins some_write = {[12'h001:12'hFFF]};
      bins all_write  = {12'hFFF};
    }

    // flush 與 opcode 類別交叉 (branch/例外路徑觸發 flush)
    cross_op_flush: cross cp_opcode_class, cp_flush;
    // flush 與 LSU lane 使用交叉 (flush 時 lane 應被清空)
    cross_flush_lsu: cross cp_flush, cp_lsu_lane;
  endgroup : cpu_mon_cg

  // 由指令 major opcode (+funct7) 分類
  function automatic opclass_e classify(logic [31:0] instr);
    casez (instr[6:0])
      7'b0110011: return (instr[25]) ? OC_MUL_DIV : OC_ALU;  // R-type (M ext: funct7[0])
      7'b0010011: return OC_ALU;                              // I-type ALU
      7'b0000011: return OC_LOAD;
      7'b0100011: return OC_STORE;
      7'b1100011,
      7'b1101111,
      7'b1100111: return OC_BRANCH;                           // BRANCH/JAL/JALR
      7'b1010111: return OC_VEC;                              // OP-V
      7'b0001011,
      7'b0101011: return OC_CRYPTO;                           // custom-0/1 (Zk*)
      default:    return OC_OTHER;
    endcase
  endfunction

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
    cpu_mon_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual orca_cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    orca_cpu_transaction tr;
    forever begin
      @(posedge vif.clk);

      // v6.3.3 coverage 取樣 (每拍)
      cov_flush    = vif.flush_valid;
      cov_lsu_lane = vif.lsu_lane_valid;
      cov_prf_wv   = vif.prf_wvalid;

      if (vif.retire_valid[0]) begin  // Monitor first retire port
        tr = orca_cpu_transaction::type_id::create("tr");
        tr.pc            = vif.retire_pc[0];
        tr.thread_id     = vif.retire_tid[0];
        tr.actual_result = vif.retire_result[0];
        tr.actual_exception = vif.retire_exception[0];
        tr.actual_exc_code  = vif.retire_exc_code[0];
        tr.instr         = vif.retire_instr[0];

        cov_opclass = classify(tr.instr);

        analysis_port.write(tr);
        `uvm_info("MONITOR", $sformatf("Observed retire: PC=%h TID=%0d RES=%h",
          tr.pc, tr.thread_id, tr.actual_result), UVM_HIGH)
      end

      cpu_mon_cg.sample();
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COVERAGE", $sformatf("CPU monitor coverage: %0.2f%%",
      cpu_mon_cg.get_coverage()), UVM_LOW)
  endfunction
endclass : orca_cpu_monitor

// ---------------------------------------------------------------------------
// Agent: Encapsulates sequencer, driver, monitor
// ---------------------------------------------------------------------------
class orca_cpu_agent extends uvm_agent;
  `uvm_component_utils(orca_cpu_agent)

  orca_cpu_sequencer sequencer;
  orca_cpu_driver    driver;
  orca_cpu_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = orca_cpu_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = orca_cpu_sequencer::type_id::create("sequencer", this);
      driver    = orca_cpu_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass : orca_cpu_agent

`endif // ORCA_CPU_AGENT_SV
