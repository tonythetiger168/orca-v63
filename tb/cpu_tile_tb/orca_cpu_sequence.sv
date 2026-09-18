//=============================================================================
// ORCA v6.3 UVM CPU Tile Sequences
// File: tb/cpu_tile_tb/orca_cpu_sequence.sv
// Description: Various test sequences for CPU Tile verification
//=============================================================================

`ifndef ORCA_CPU_SEQUENCE_SV
`define ORCA_CPU_SEQUENCE_SV

// ---------------------------------------------------------------------------
// Base Sequence
// ---------------------------------------------------------------------------
class orca_cpu_base_sequence extends uvm_sequence #(orca_cpu_transaction);
  `uvm_object_utils(orca_cpu_base_sequence)

  orca_tb_config cfg;
  int transaction_count;

  function new(string name = "orca_cpu_base_sequence");
    super.new(name);
  endfunction

  task pre_body();
    if (starting_phase != null) begin
      starting_phase.raise_objection(this, "Starting sequence");
    end
    if (!uvm_config_db#(orca_tb_config)::get(null, "", "cfg", cfg))
      cfg = new();
    transaction_count = cfg.num_transactions;
  endtask

  task post_body();
    if (starting_phase != null) begin
      starting_phase.drop_objection(this, "Finished sequence");
    end
  endtask
endclass : orca_cpu_base_sequence

// ---------------------------------------------------------------------------
// Random ALU Instruction Sequence
// ---------------------------------------------------------------------------
class orca_cpu_alu_sequence extends orca_cpu_base_sequence;
  `uvm_object_utils(orca_cpu_alu_sequence)

  function new(string name = "orca_cpu_alu_sequence");
    super.new(name);
  endfunction

  task body();
    orca_cpu_transaction tr;
    `uvm_info("SEQ", "Starting ALU random sequence", UVM_MEDIUM)

    for (int i = 0; i < transaction_count; i++) begin
      tr = orca_cpu_transaction::type_id::create($sformatf("tr_%0d", i));
      start_item(tr);

      // Randomize with ALU-specific constraints
      if (!tr.randomize() with {
        op_type inside {OP_ALU, OP_ALUI};
        rs1_addr != 0;  // x0 is hardwired to 0
        rs2_addr != 0;
        rd_addr  != 0;
      }) begin
        `uvm_error("SEQ", "Randomization failed")
      end

      // Encode a simple ADD instruction
      tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};

      finish_item(tr);
    end
    `uvm_info("SEQ", $sformatf("Completed %0d ALU transactions", transaction_count), UVM_MEDIUM)
  endtask
endclass : orca_cpu_alu_sequence

// ---------------------------------------------------------------------------
// SMT Stress Sequence (4 threads interleaved)
// ---------------------------------------------------------------------------
class orca_cpu_smt_sequence extends orca_cpu_base_sequence;
  `uvm_object_utils(orca_cpu_smt_sequence)

  function new(string name = "orca_cpu_smt_sequence");
    super.new(name);
  endfunction

  task body();
    orca_cpu_transaction tr;
    `uvm_info("SEQ", "Starting SMT stress sequence", UVM_MEDIUM)

    // Launch 4 parallel threads, each generating instructions for one TID
    fork
      begin
        for (int i = 0; i < transaction_count/4; i++) begin
          tr = orca_cpu_transaction::type_id::create($sformatf("smt0_tr_%0d", i));
          start_item(tr);
          if (!tr.randomize() with { thread_id == 0; op_type inside {OP_ALU, OP_ALUI}; })
            `uvm_error("SEQ", "Randomization failed")
          tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
          finish_item(tr);
        end
      end
      begin
        for (int i = 0; i < transaction_count/4; i++) begin
          tr = orca_cpu_transaction::type_id::create($sformatf("smt1_tr_%0d", i));
          start_item(tr);
          if (!tr.randomize() with { thread_id == 1; op_type inside {OP_ALU, OP_LOAD}; })
            `uvm_error("SEQ", "Randomization failed")
          tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
          finish_item(tr);
        end
      end
      begin
        for (int i = 0; i < transaction_count/4; i++) begin
          tr = orca_cpu_transaction::type_id::create($sformatf("smt2_tr_%0d", i));
          start_item(tr);
          if (!tr.randomize() with { thread_id == 2; op_type inside {OP_ALU, OP_BRANCH}; })
            `uvm_error("SEQ", "Randomization failed")
          tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
          finish_item(tr);
        end
      end
      begin
        for (int i = 0; i < transaction_count/4; i++) begin
          tr = orca_cpu_transaction::type_id::create($sformatf("smt3_tr_%0d", i));
          start_item(tr);
          if (!tr.randomize() with { thread_id == 3; op_type inside {OP_ALU, OP_STORE}; })
            `uvm_error("SEQ", "Randomization failed")
          tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
          finish_item(tr);
        end
      end
    join

    `uvm_info("SEQ", "Completed SMT stress sequence", UVM_MEDIUM)
  endtask
endclass : orca_cpu_smt_sequence

// ---------------------------------------------------------------------------
// Exception Test Sequence
// ---------------------------------------------------------------------------
class orca_cpu_exception_sequence extends orca_cpu_base_sequence;
  `uvm_object_utils(orca_cpu_exception_sequence)

  function new(string name = "orca_cpu_exception_sequence");
    super.new(name);
  endfunction

  task body();
    orca_cpu_transaction tr;
    `uvm_info("SEQ", "Starting exception test sequence", UVM_MEDIUM)

    // Normal instructions
    for (int i = 0; i < 10; i++) begin
      tr = orca_cpu_transaction::type_id::create($sformatf("exc_tr_%0d", i));
      start_item(tr);
      if (!tr.randomize() with { op_type inside {OP_ALU, OP_ALUI}; })
        `uvm_error("SEQ", "Randomization failed")
      tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
      finish_item(tr);
    end

    // Misaligned load (should trigger exception)
    tr = orca_cpu_transaction::type_id::create("exc_misalign");
    start_item(tr);
    if (!tr.randomize() with { op_type == OP_LOAD; })
      `uvm_error("SEQ", "Randomization failed")
    tr.instr = {12'h001, tr.rs1_addr, 3'b011, tr.rd_addr, 7'b0000011};  // LD with misaligned
    tr.rs1_data = 64'h8000_0001;  // Misaligned address
    finish_item(tr);

    // More instructions after exception (should be flushed)
    for (int i = 0; i < 5; i++) begin
      tr = orca_cpu_transaction::type_id::create($sformatf("post_exc_%0d", i));
      start_item(tr);
      if (!tr.randomize() with { op_type inside {OP_ALU}; })
        `uvm_error("SEQ", "Randomization failed")
      tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
      finish_item(tr);
    end

    `uvm_info("SEQ", "Completed exception test sequence", UVM_MEDIUM)
  endtask
endclass : orca_cpu_exception_sequence

// ---------------------------------------------------------------------------
// v6.3.3: ROB Flush / Freelist Recovery Sequence
// 混合 branch (mispredict flush) 與 misaligned load (例外 flush),
// 觸發 cmt_rob 精確 flush 與 rnu_freelist 全量重建:
//   - 每 round 先送一串 ALU (建立 ROB/freelist 壓力)
//   - 接著一個 taken branch (BPU 預設 not-taken => mispredict => 清年輕 entry)
//   - 每 3 round 插入一個 misaligned load (例外 => retire 頭端精確 flush)
//   - flush 後再送 ALU (flush victims + 驗證 freelist 恢復後可繼續分配)
// ---------------------------------------------------------------------------
class orca_cpu_flush_seq extends orca_cpu_base_sequence;
  `uvm_object_utils(orca_cpu_flush_seq)

  int num_rounds = 8;

  function new(string name = "orca_cpu_flush_seq");
    super.new(name);
  endfunction

  task body();
    orca_cpu_transaction tr;
    int rounds = (transaction_count / 16 > num_rounds) ? transaction_count / 16 : num_rounds;
    `uvm_info("SEQ", "Starting flush (branch/exception mix) sequence", UVM_MEDIUM)

    for (int r = 0; r < rounds; r++) begin
      // Phase 1: ALU burst — 填充 ROB 並消耗 freelist
      for (int i = 0; i < 8; i++) begin
        tr = orca_cpu_transaction::type_id::create($sformatf("fl_r%0d_alu%0d", r, i));
        start_item(tr);
        if (!tr.randomize() with {
          op_type inside {OP_ALU, OP_ALUI};
          rs1_addr != 0; rs2_addr != 0; rd_addr != 0;
        }) `uvm_error("SEQ", "Randomization failed")
        tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
        finish_item(tr);
      end

      // Phase 2: taken branch — 預測 not-taken => mispredict => ROB 精確 flush
      //          (僅清比分支年輕的 entry, tail 回捲)
      tr = orca_cpu_transaction::type_id::create($sformatf("fl_r%0d_br", r));
      start_item(tr);
      if (!tr.randomize() with { op_type == OP_BRANCH; rs1_addr == 0; rs2_addr == 0; })
        `uvm_error("SEQ", "Randomization failed")
      // BEQ x0, x0, +8 (無條件成立 => taken)
      tr.instr = {7'b0000000, 5'b00000, 5'b00000, 3'b000, 5'b00100, 7'b1100011};
      finish_item(tr);

      // Phase 3: 每 3 round 插一個 misaligned load — 例外須在 retire 頭端
      //          才觸發 flush 並清空該 thread ROB 分區 + freelist 全量重建
      if (r % 3 == 2) begin
        tr = orca_cpu_transaction::type_id::create($sformatf("fl_r%0d_exc", r));
        start_item(tr);
        if (!tr.randomize() with { op_type == OP_LOAD; rs1_addr != 0; rd_addr != 0; })
          `uvm_error("SEQ", "Randomization failed")
        tr.instr    = {12'h001, tr.rs1_addr, 3'b011, tr.rd_addr, 7'b0000011}; // LD
        tr.rs1_data = 64'h8000_0001;  // misaligned base
        finish_item(tr);
      end

      // Phase 4: flush victims — 理應被清掉的年輕 uop; 同時驗證 flush 後
      //          freelist 恢復, 後續 uop 仍能取得新 prd
      for (int i = 0; i < 6; i++) begin
        tr = orca_cpu_transaction::type_id::create($sformatf("fl_r%0d_vic%0d", r, i));
        start_item(tr);
        if (!tr.randomize() with {
          op_type inside {OP_ALU}; rs1_addr != 0; rs2_addr != 0; rd_addr != 0;
        }) `uvm_error("SEQ", "Randomization failed")
        tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
        finish_item(tr);
      end
    end

    `uvm_info("SEQ", $sformatf("Completed %0d flush rounds", rounds), UVM_MEDIUM)
  endtask
endclass : orca_cpu_flush_seq

// ---------------------------------------------------------------------------
// v6.3.3: LSU x4 Lane Stress Sequence
// 4 個 thread 同時送出高密度 LD/ST 混合, 打滿 isu_mem 4 條 lane
// (issue -> AGU -> DTLB -> dcache -> MSHR 路徑)
// ---------------------------------------------------------------------------
class orca_cpu_lsu_stress_seq extends orca_cpu_base_sequence;
  `uvm_object_utils(orca_cpu_lsu_stress_seq)

  function new(string name = "orca_cpu_lsu_stress_seq");
    super.new(name);
  endfunction

  // 每個 thread 的 LD/ST 混合產生器 (SW 佔 ~40% 以同時壓 STQ/forwarding)
  task gen_mem_traffic(int tid, int count);
    orca_cpu_transaction tr;
    for (int i = 0; i < count; i++) begin
      tr = orca_cpu_transaction::type_id::create($sformatf("lsu_t%0d_tr_%0d", tid, i));
      start_item(tr);
      if (!tr.randomize() with {
        thread_id == tid;
        op_type dist {OP_LOAD := 60, OP_STORE := 40};
        rs1_addr != 0;
      }) `uvm_error("SEQ", "Randomization failed")
      if (tr.op_type == OP_LOAD) begin
        // LW rd, imm(rs1) — 對齊位址 (imm[1:0]==0)
        tr.instr    = {10'h001, 2'b00, tr.rs1_addr, 3'b010, tr.rd_addr, 7'b0000011};
        tr.rs1_data = 64'h0000_1000 + (i * 64);  // 分散到不同 cache line
      end else begin
        // SW rs2, imm(rs1)
        tr.instr    = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b010, 5'b00100, 7'b0100011};
        tr.rs1_data = 64'h0000_1000 + (i * 64);
        tr.rs2_data = 64'hDEAD_BEEF_0000 + i;
      end
      finish_item(tr);
    end
  endtask

  task body();
    `uvm_info("SEQ", "Starting LSU x4 lane stress sequence", UVM_MEDIUM)

    // 4 thread 並行 => decode/dispatch 同拍可見多個 mem uop, 填滿 4 lane
    fork
      gen_mem_traffic(0, transaction_count / 4);
      gen_mem_traffic(1, transaction_count / 4);
      gen_mem_traffic(2, transaction_count / 4);
      gen_mem_traffic(3, transaction_count / 4);
    join

    `uvm_info("SEQ", "Completed LSU stress sequence", UVM_MEDIUM)
  endtask
endclass : orca_cpu_lsu_stress_seq

// ---------------------------------------------------------------------------
// v6.3.3: MUL / VEC / CRYPTO Operand Path Sequence
// 驗證 PRF 讀埠供應 exu_mul (port 10/11), exu_vec (port 12/13),
// exu_crypto (port 7/8/9) 操作數, 以及對應寫回埠 (wport 3/4/2)
// ---------------------------------------------------------------------------
class orca_cpu_mul_vec_seq extends orca_cpu_base_sequence;
  `uvm_object_utils(orca_cpu_mul_vec_seq)

  function new(string name = "orca_cpu_mul_vec_seq");
    super.new(name);
  endfunction

  task body();
    orca_cpu_transaction tr;
    `uvm_info("SEQ", "Starting MUL/VEC/CRYPTO operand path sequence", UVM_MEDIUM)

    // 先以 ALU 建立來源暫存器值 (確保 PRF 有已知操作數可讀)
    for (int i = 0; i < 4; i++) begin
      tr = orca_cpu_transaction::type_id::create($sformatf("mv_setup_%0d", i));
      start_item(tr);
      if (!tr.randomize() with {
        op_type == OP_ALUI; rs1_addr == 0; rd_addr == (i + 1);
      }) `uvm_error("SEQ", "Randomization failed")
      tr.instr = {12'h010 + i[11:0], 5'b00000, 3'b000, tr.rd_addr, 7'b0010011}; // ADDI
      finish_item(tr);
    end

    // 主體: MUL/DIV/VEC/CRYPTO 混合, rs1/rs2 依賴前面的暫存器
    for (int i = 0; i < transaction_count; i++) begin
      tr = orca_cpu_transaction::type_id::create($sformatf("mv_tr_%0d", i));
      start_item(tr);
      if (!tr.randomize() with {
        op_type inside {OP_MUL, OP_DIV, OP_VEC, OP_CRYPTO};
        rs1_addr inside {[1:4]}; rs2_addr inside {[1:4]}; rd_addr != 0;
      }) `uvm_error("SEQ", "Randomization failed")

      case (tr.op_type)
        // MUL rd, rs1, rs2 (funct7=0000001, funct3=000)
        OP_MUL: tr.instr = {7'b0000001, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
        // DIV rd, rs1, rs2 (funct7=0000001, funct3=100)
        OP_DIV: tr.instr = {7'b0000001, tr.rs2_addr, tr.rs1_addr, 3'b100, tr.rd_addr, 7'b0110011};
        // VADD.VV vd, vs1, vs2 (OP-V major opcode)
        OP_VEC: tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b1010111};
        // CRYPTO: custom-0 major opcode (Zk* 類)
        OP_CRYPTO: tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0001011};
        default: tr.instr = {7'b0000000, tr.rs2_addr, tr.rs1_addr, 3'b000, tr.rd_addr, 7'b0110011};
      endcase
      finish_item(tr);
    end

    `uvm_info("SEQ", $sformatf("Completed %0d MUL/VEC/CRYPTO transactions",
      transaction_count), UVM_MEDIUM)
  endtask
endclass : orca_cpu_mul_vec_seq

// ---------------------------------------------------------------------------
// AIX Co-simulation Sequence
// ---------------------------------------------------------------------------
class orca_aix_sequence extends uvm_sequence #(orca_aix_transaction);
  `uvm_object_utils(orca_aix_sequence)

  function new(string name = "orca_aix_sequence");
    super.new(name);
  endfunction

  task body();
    orca_aix_transaction tr;
    `uvm_info("SEQ", "Starting AIX sequence", UVM_MEDIUM)

    // AIX.SEND: Send tensor descriptor
    tr = orca_aix_transaction::type_id::create("aix_send");
    start_item(tr);
    if (!tr.randomize() with { aix_op == AIX_SEND; dst_tile inside {[0:3]}; })
      `uvm_error("SEQ", "Randomization failed")
    tr.tdb.base_addr = 64'h9000_0000;
    tr.tdb.dim_n = 64;
    tr.tdb.dim_c = 128;
    tr.tdb.dim_h = 56;
    tr.tdb.dim_w = 56;
    tr.tdb.data_type = AI_DTYPE_BF16;
    finish_item(tr);

    // AIX.SYNC: Wait for completion
    tr = orca_aix_transaction::type_id::create("aix_sync");
    start_item(tr);
    if (!tr.randomize() with { aix_op == AIX_SYNC; })
      `uvm_error("SEQ", "Randomization failed")
    finish_item(tr);

    // AIX.QUERY: Check status
    tr = orca_aix_transaction::type_id::create("aix_query");
    start_item(tr);
    if (!tr.randomize() with { aix_op == AIX_QUERY; })
      `uvm_error("SEQ", "Randomization failed")
    finish_item(tr);

    `uvm_info("SEQ", "Completed AIX sequence", UVM_MEDIUM)
  endtask
endclass : orca_aix_sequence

`endif // ORCA_CPU_SEQUENCE_SV
