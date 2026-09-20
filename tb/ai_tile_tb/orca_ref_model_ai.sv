// SPDX-License-Identifier: Apache-2.0
//=============================================================================
// ORCA v6.3 UVM AI Tile Reference Model
// File: tb/ai_tile_tb/orca_ref_model_ai.sv
// Description: Python-style C++ reference model for AI accelerator verification
//              Simulates systolic array computation for golden reference
//=============================================================================

`ifndef ORCA_REF_MODEL_AI_SV
`define ORCA_REF_MODEL_AI_SV

class orca_ref_model_ai extends uvm_component;
  `uvm_component_utils(orca_ref_model_ai)

  // ---------------------------------------------------------------------------
  // Reference State
  // ---------------------------------------------------------------------------
  // L2 SRAM model (64 MB)
  logic [7:0] l2_sram [0:(64*1024*1024)-1];

  // HBM3 model (24 GB per tile)
  logic [7:0] hbm3_mem [0:(24*1024*1024*1024)-1];

  // PE accumulator state (64x64 array)
  real pe_accumulator [64][64];

  // Task queue
  typedef struct {
    aix_tdb_t tdb;
    logic [63:0] start_cycle;
    logic [63:0] end_cycle;
    logic completed;
  } ai_task_t;

  ai_task_t task_queue[$];
  int max_queue_depth;

  // Performance counters
  longint total_macs;
  longint total_cycles;
  longint total_tasks;

  uvm_analysis_imp #(orca_aix_transaction, orca_ref_model_ai) aix_analysis_imp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aix_analysis_imp = new("aix_analysis_imp", this);
    max_queue_depth = 0;
    total_macs = 0;
    total_cycles = 0;
    total_tasks = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Initialize memory
    foreach (l2_sram[i]) l2_sram[i] = 8'h00;
    foreach (hbm3_mem[i]) hbm3_mem[i] = 8'h00;
    foreach (pe_accumulator[r,c]) pe_accumulator[r][c] = 0.0;
  endfunction

  // ---------------------------------------------------------------------------
  // AIX Transaction Handler
  // ---------------------------------------------------------------------------
  function void write(orca_aix_transaction tr);
    case (tr.aix_op)
      AIX_SEND: handle_send(tr);
      AIX_SYNC: handle_sync(tr);
      AIX_QUERY: handle_query(tr);
      AIX_PREF: handle_prefetch(tr);
      default: `uvm_warning("REF_AI", "Unknown AIX op")
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // AIX.SEND Handler
  // ---------------------------------------------------------------------------
  function void handle_send(orca_aix_transaction tr);
    ai_task_t new_task;
    new_task.tdb = tr.tdb;
    new_task.start_cycle = $time / 1000;  // Convert to cycles
    new_task.completed = 1'b0;

    // Calculate expected compute cycles
    longint expected_cycles;
    longint macs;

    macs = calculate_macs(tr.tdb);
    expected_cycles = estimate_cycles(tr.tdb, macs);

    new_task.end_cycle = new_task.start_cycle + expected_cycles;

    task_queue.push_back(new_task);
    total_tasks++;
    total_macs += macs;

    `uvm_info("REF_AI", $sformatf("Task queued: base=%h dims=%0dx%0dx%0dx%0d MACs=%0d est_cycles=%0d",
      tr.tdb.base_addr, tr.tdb.dim_n, tr.tdb.dim_c, tr.tdb.dim_h, tr.tdb.dim_w,
      macs, expected_cycles), UVM_MEDIUM)

    // Update max queue depth
    if (task_queue.size() > max_queue_depth)
      max_queue_depth = task_queue.size();
  endfunction

  // ---------------------------------------------------------------------------
  // AIX.SYNC Handler
  // ---------------------------------------------------------------------------
  function void handle_sync(orca_aix_transaction tr);
    // Wait for all tasks to complete
    longint current_cycle = $time / 1000;

    foreach (task_queue[i]) begin
      if (!task_queue[i].completed) begin
        if (current_cycle >= task_queue[i].end_cycle) begin
          task_queue[i].completed = 1'b1;

          // Execute the computation in reference model
          execute_task(task_queue[i]);

          `uvm_info("REF_AI", $sformatf("Task completed: base=%h cycles=%0d",
            task_queue[i].tdb.base_addr,
            task_queue[i].end_cycle - task_queue[i].start_cycle), UVM_MEDIUM)
        end
      end
    end

    // Remove completed tasks
    for (int i = task_queue.size()-1; i >= 0; i--) begin
      if (task_queue[i].completed)
        task_queue.delete(i);
    end
  endfunction

  // ---------------------------------------------------------------------------
  // AIX.QUERY Handler
  // ---------------------------------------------------------------------------
  function void handle_query(orca_aix_transaction tr);
    aix_status_t status;
    longint current_cycle = $time / 1000;

    status.progress = (total_tasks > 0) ? 10000 : 0;
    status.temperature = 65;  // Simulated
    status.power_w = 150;     // Simulated
    status.hbm_util = 75;     // Simulated
    status.cu_util = 80;      // Simulated
    status.queue_depth = task_queue.size();
    status.error_flag = 1'b0;

    `uvm_info("REF_AI", $sformatf("Status: queue=%0d progress=%0d%% power=%0dW",
      status.queue_depth, status.progress/100, status.power_w), UVM_HIGH)
  endfunction

  // ---------------------------------------------------------------------------
  // AIX.PREF Handler
  // ---------------------------------------------------------------------------
  function void handle_prefetch(orca_aix_transaction tr);
    // Simulate prefetch: copy data from HBM3 to L2
    longint size_bytes = 1024 * 1024;  // 1MB prefetch
    longint src_addr = tr.tdb.base_addr;
    longint dst_addr = tr.tdb.dst_l2_offset;

    for (longint i = 0; i < size_bytes; i++) begin
      if (src_addr + i < $size(hbm3_mem) && dst_addr + i < $size(l2_sram))
        l2_sram[dst_addr + i] = hbm3_mem[src_addr + i];
    end

    `uvm_info("REF_AI", $sformatf("Prefetch: %0d bytes from HBM3 %h to L2 %h",
      size_bytes, src_addr, dst_addr), UVM_HIGH)
  endfunction

  // ---------------------------------------------------------------------------
  // MAC Calculation
  // ---------------------------------------------------------------------------
  function longint calculate_macs(input aix_tdb_t tdb);
    longint macs;
    // N x C x H x W (simplified: assume 1 MAC per output element per channel)
    macs = tdb.dim_n * tdb.dim_c * tdb.dim_h * tdb.dim_w;
    return macs;
  endfunction

  // ---------------------------------------------------------------------------
  // Cycle Estimation
  // ---------------------------------------------------------------------------
  function longint estimate_cycles(input aix_tdb_t tdb, input longint macs);
    longint cycles;
    int pe_array_size = 64 * 64;  // 4096 PEs
    int utilization = 24;          // 24% target utilization

    // Base cycles = MACs / (PEs * utilization)
    cycles = (macs * 100) / (pe_array_size * utilization);

    // Add overhead: DMA setup, pipeline fill, memory latency
    cycles += 100;  // Setup overhead
    cycles += (macs / (819 * 1024 * 1024 / 8));  // HBM3 bandwidth limit

    return cycles;
  endfunction

  // ---------------------------------------------------------------------------
  // Task Execution (Golden Reference)
  // ---------------------------------------------------------------------------
  function void execute_task(input ai_task_t task);
    aix_tdb_t tdb = task.tdb;
    real result [64][64];
    int N = tdb.dim_n;
    int C = tdb.dim_c;
    int H = tdb.dim_h;
    int W = tdb.dim_w;

    // Simplified matrix multiplication reference
    // For a Conv2D: output[n][h][w] = sum(c, input[n][c][h][w] * weight[c])
    for (int n = 0; n < N && n < 64; n++) begin
      for (int h = 0; h < H && h < 64; h++) begin
        for (int w = 0; w < W && w < 64; w++) begin
          real sum = 0.0;
          for (int c = 0; c < C && c < 64; c++) begin
            // Read from L2 SRAM (simplified addressing)
            longint act_addr = tdb.dst_l2_offset + ((n*C + c)*H + h)*W + w;
            longint wgt_addr = tdb.dst_l2_offset + 32*1024*1024 + c*64;  // Weight at offset + 32MB

            real activation = (act_addr < $size(l2_sram)) ? $itor(l2_sram[act_addr]) : 0.0;
            real weight_val = (wgt_addr < $size(l2_sram)) ? $itor(l2_sram[wgt_addr]) : 0.0;

            sum += activation * weight_val;
          end
          result[n][h*W + w] = sum;
        end
      end
    end

    // Store result back to L2
    for (int n = 0; n < N && n < 64; n++) begin
      for (int h = 0; h < H && h < 64; h++) begin
        for (int w = 0; w < W && w < 64; w++) begin
          longint out_addr = tdb.dst_l2_offset + 48*1024*1024 + ((n*H + h)*W + w) * 4;
          if (out_addr + 3 < $size(l2_sram)) begin
            int val = $rtoi(result[n][h*W + w]);
            l2_sram[out_addr]   = val[7:0];
            l2_sram[out_addr+1] = val[15:8];
            l2_sram[out_addr+2] = val[23:16];
            l2_sram[out_addr+3] = val[31:24];
          end
        end
      end
    end

    `uvm_info("REF_AI", "Task execution complete (golden reference)", UVM_HIGH)
  endfunction

  // ---------------------------------------------------------------------------
  // Report Phase
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("REF_AI", $sformatf("
========================================
" +
      "AI Reference Model Summary:
" +
      "  Total Tasks:      %0d
" +
      "  Total MACs:       %0d
" +
      "  Max Queue Depth:  %0d
" +
      "  Avg Cycles/Task:  %0d
" +
      "========================================",
      total_tasks, total_macs, max_queue_depth,
      (total_tasks > 0) ? (total_cycles / total_tasks) : 0), UVM_LOW)
  endfunction

endclass : orca_ref_model_ai

`endif // ORCA_REF_MODEL_AI_SV
