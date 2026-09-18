//=============================================================================
// ORCA v6.3 ZEN++ Branch Prediction Unit (BPU)
// File: rtl/cpu/frontend/ifu_bpu.sv
// Description: TAGE-SC-L + Perceptron Hybrid with Loop Predictor
//              3-level hierarchy: µBTB -> TAGE-SC-L -> ITA/RAS
//=============================================================================

`include "orca_pkg.sv"

module ifu_bpu
  import orca_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // ---------------------------------------------------------------------------
  // Fetch PC Interface
  // ---------------------------------------------------------------------------
  input  logic [63:0] fetch_pc [SMT_THREADS],
  input  logic        fetch_valid [SMT_THREADS],
  output bpu_info_t   bpu_info [SMT_THREADS],
  output logic        bpu_ready,

  // ---------------------------------------------------------------------------
  // Update Interface (from Commit/ROB)
  // ---------------------------------------------------------------------------
  input  logic        update_valid,
  input  logic [63:0] update_pc,
  input  logic        update_taken,
  input  logic [63:0] update_target,
  input  logic        update_mispredict,
  input  tid_t        update_tid,
  input  logic        update_is_call,
  input  logic        update_is_return,
  input  logic        update_is_indirect,

  // ---------------------------------------------------------------------------
  // Flush Interface
  // ---------------------------------------------------------------------------
  input  logic        flush_valid,
  input  tid_t        flush_tid
);

  import orca_pkg::*;

  // ---------------------------------------------------------------------------
  // L0: µBTB (Micro-Branch Target Buffer)
  // ---------------------------------------------------------------------------
  localparam int UBTB_ENTRIES = 128;
  localparam int UBTB_TAG_BITS = 10;

  typedef struct packed {
    logic [UBTB_TAG_BITS-1:0] tag;
    logic [63:0]               target;
    logic                      valid;
    logic                      is_call;
    logic                      is_return;
  } ubtb_entry_t;

  ubtb_entry_t [UBTB_ENTRIES-1:0] ubtb [SMT_THREADS];
  logic [$clog2(UBTB_ENTRIES)-1:0] ubtb_idx [SMT_THREADS];
  logic [UBTB_TAG_BITS-1:0] ubtb_tag [SMT_THREADS];

  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_ubtb
      assign ubtb_idx[t] = fetch_pc[t][$clog2(UBTB_ENTRIES)+1:2];
      assign ubtb_tag[t] = fetch_pc[t][UBTB_TAG_BITS+$clog2(UBTB_ENTRIES)+1:$clog2(UBTB_ENTRIES)+2];

      // µBTB lookup (1-cycle latency)
      always_ff @(posedge clk) begin
        if (fetch_valid[t]) begin
          if (ubtb[t][ubtb_idx[t]].valid &&
              ubtb[t][ubtb_idx[t]].tag == ubtb_tag[t]) begin
            bpu_info[t].predicted_taken <= 1'b1;
            bpu_info[t].target_pc       <= ubtb[t][ubtb_idx[t]].target;
            bpu_info[t].is_return       <= ubtb[t][ubtb_idx[t]].is_return;
            bpu_info[t].is_call         <= ubtb[t][ubtb_idx[t]].is_call;
          end else begin
            bpu_info[t].predicted_taken <= 1'b0;
            bpu_info[t].target_pc       <= fetch_pc[t] + 4;
            bpu_info[t].is_return       <= 1'b0;
            bpu_info[t].is_call         <= 1'b0;
          end
        end
      end

      // µBTB update
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int i = 0; i < UBTB_ENTRIES; i++) ubtb[t][i].valid <= 1'b0;
        end else if (update_valid && update_tid == t && update_mispredict) begin
          ubtb[t][ubtb_idx[t]].tag       <= ubtb_tag[t];
          ubtb[t][ubtb_idx[t]].target    <= update_target;
          ubtb[t][ubtb_idx[t]].valid     <= 1'b1;
          ubtb[t][ubtb_idx[t]].is_call   <= update_is_call;
          ubtb[t][ubtb_idx[t]].is_return <= update_is_return;
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // L1: TAGE-SC-L (TAgged GEometric history length + Statistical Corrector)
  // ---------------------------------------------------------------------------
  localparam int TAGE_TABLES = 16;
  localparam int TAGE_ENTRIES = 16384;  // 16K per table
  localparam int TAGE_TAG_BITS = 12;
  localparam int TAGE_CTR_BITS = 3;     // 3-bit saturating counter
  localparam int TAGE_USEFUL_BITS = 2;

  // History lengths for each table (geometric series)
  localparam int TAGE_HISTORY[TAGE_TABLES] = '{4, 8, 16, 32, 64, 128, 256, 512,
                                                640, 768, 896, 1024, 1280, 1536, 1792, 2048};

  typedef struct packed {
    logic [TAGE_TAG_BITS-1:0] tag;
    logic [TAGE_CTR_BITS-1:0] ctr;      // Prediction counter: 0-7
    logic [TAGE_USEFUL_BITS-1:0] useful;
    logic valid;
  } tage_entry_t;

  tage_entry_t [TAGE_ENTRIES-1:0] tage_tables [SMT_THREADS][TAGE_TABLES];

  // Global History Register (GHR) per thread
  logic [2047:0] ghr [SMT_THREADS];
  logic [63:0]   ghr_hash [SMT_THREADS];

  // Folded history for tag/index computation
  function automatic logic [TAGE_TAG_BITS-1:0] compute_tag(
    input logic [63:0] pc,
    input logic [2047:0] history,
    input int table_idx
  );
    logic [TAGE_TAG_BITS-1:0] tag;
    logic [63:0] folded_hist;
    int hlen = TAGE_HISTORY[table_idx];

    // Fold history to 64 bits
    folded_hist = '0;
    for (int i = 0; i < hlen; i += 64) begin
      int len = (i + 64 <= hlen) ? 64 : (hlen - i);
      folded_hist ^= history[i +: len];
    end

    tag = pc[2 +: TAGE_TAG_BITS] ^ folded_hist[TAGE_TAG_BITS-1:0];
    return tag;
  endfunction

  function automatic logic [$clog2(TAGE_ENTRIES)-1:0] compute_index(
    input logic [63:0] pc,
    input logic [2047:0] history,
    input int table_idx
  );
    logic [$clog2(TAGE_ENTRIES)-1:0] idx;
    logic [63:0] folded_hist;
    int hlen = TAGE_HISTORY[table_idx];

    folded_hist = '0;
    for (int i = 0; i < hlen; i += 64) begin
      int len = (i + 64 <= hlen) ? 64 : (hlen - i);
      folded_hist ^= history[i +: len];
    end

    idx = pc[2 +: $clog2(TAGE_ENTRIES)] ^ folded_hist[$clog2(TAGE_ENTRIES)-1:0];
    return idx;
  endfunction

  // TAGE prediction (2-cycle latency)
  logic [TAGE_CTR_BITS-1:0] tage_pred_ctr [SMT_THREADS];
  logic [TAGE_TABLES-1:0]   tage_hit [SMT_THREADS];
  logic [$clog2(TAGE_TABLES):0] tage_provider [SMT_THREADS];
  logic                       tage_pred_taken [SMT_THREADS];

  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_tage_pred
      always_ff @(posedge clk) begin
        if (fetch_valid[t]) begin
          // Search tables from longest history to shortest
          tage_hit[t] = '0;
          tage_provider[t] = '0;
          tage_pred_ctr[t] = 3'b100;  // Default weakly not-taken

          for (int tbl = TAGE_TABLES-1; tbl >= 0; tbl--) begin
            logic [$clog2(TAGE_ENTRIES)-1:0] idx;
            logic [TAGE_TAG_BITS-1:0] tag;
            idx = compute_index(fetch_pc[t], ghr[t], tbl);
            tag = compute_tag(fetch_pc[t], ghr[t], tbl);

            if (tage_tables[t][tbl][idx].valid &&
                tage_tables[t][tbl][idx].tag == tag) begin
              tage_hit[t][tbl] = 1'b1;
              tage_provider[t] = tbl;
              tage_pred_ctr[t] = tage_tables[t][tbl][idx].ctr;
              break;  // Use longest matching history
            end
          end

          // Predict taken if counter >= 4 (middle of 0-7 range)
          tage_pred_taken[t] = (tage_pred_ctr[t] >= 3'b100);
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Statistical Corrector (SC)
  // ---------------------------------------------------------------------------
  localparam int SC_ENTRIES = 65536;  // 64K entries
  localparam int SC_CTR_BITS = 6;     // 6-bit signed counter

  logic signed [SC_CTR_BITS-1:0] sc_table [SMT_THREADS][SC_ENTRIES];
  logic signed [SC_CTR_BITS-1:0] sc_pred [SMT_THREADS];
  logic                          sc_override [SMT_THREADS];

  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_sc
      always_ff @(posedge clk) begin
        if (fetch_valid[t]) begin
          logic [$clog2(SC_ENTRIES)-1:0] sc_idx;
          sc_idx = compute_index(fetch_pc[t], ghr[t], 0) ^
                   compute_index(fetch_pc[t], ghr[t], TAGE_TABLES-1);
          sc_pred[t] <= sc_table[t][sc_idx];
          // Override TAGE if SC is confident (|counter| > threshold)
          sc_override[t] <= (sc_pred[t] > 20) || (sc_pred[t] < -20);
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Loop Predictor (LP)
  // ---------------------------------------------------------------------------
  localparam int LP_ENTRIES = 256;
  localparam int LP_ITER_BITS = 14;  // Max 16K iterations

  typedef struct packed {
    logic [63:0] tag;
    logic [LP_ITER_BITS-1:0] iter_count;
    logic [LP_ITER_BITS-1:0] iter_current;
    logic valid;
    logic confident;
  } lp_entry_t;

  lp_entry_t [LP_ENTRIES-1:0] lp_table [SMT_THREADS];

  // ---------------------------------------------------------------------------
  // L2: Indirect Target Array (ITA) + Return Address Stack (RAS)
  // ---------------------------------------------------------------------------
  localparam int ITA_ENTRIES = 4096;
  localparam int RAS_DEPTH = 64;

  typedef struct packed {
    logic [63:0] target;
    logic [11:0] tag;
    logic valid;
  } ita_entry_t;

  ita_entry_t [ITA_ENTRIES-1:0] ita [SMT_THREADS];
  logic [63:0] ras [SMT_THREADS][RAS_DEPTH];
  logic [$clog2(RAS_DEPTH)-1:0] ras_ptr [SMT_THREADS];

  // ---------------------------------------------------------------------------
  // Final Prediction Mux
  // ---------------------------------------------------------------------------
  generate
    for (genvar t = 0; t < SMT_THREADS; t++) begin : gen_final_pred
      always_ff @(posedge clk) begin
        if (fetch_valid[t]) begin
          // Priority: µBTB (unconditional) > TAGE+SC (conditional) > LP
          if (bpu_info[t].predicted_taken && (bpu_info[t].is_call || bpu_info[t].is_return)) begin
            // µBTB already handled unconditional branches
          end else begin
            // Conditional branch: use TAGE + SC
            if (sc_override[t]) begin
              bpu_info[t].predicted_taken <= (sc_pred[t] > 0);
            end else begin
              bpu_info[t].predicted_taken <= tage_pred_taken[t];
            end
          end
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Update Logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int t = 0; t < SMT_THREADS; t++) begin
        ghr[t] <= '0;
        ras_ptr[t] <= '0;
        for (int i = 0; i < RAS_DEPTH; i++) ras[t][i] <= '0;
      end
    end else if (update_valid) begin
      int t = update_tid;

      // Update GHR
      ghr[t] <= {ghr[t][2046:0], update_taken};

      // Update TAGE provider table
      if (tage_hit[t][tage_provider[t]]) begin
        logic [$clog2(TAGE_ENTRIES)-1:0] idx;
        idx = compute_index(update_pc, ghr[t], tage_provider[t]);
        // Saturating counter update
        if (update_taken && tage_tables[t][tage_provider[t]][idx].ctr < 3'b111)
          tage_tables[t][tage_provider[t]][idx].ctr <= tage_tables[t][tage_provider[t]][idx].ctr + 1;
        else if (!update_taken && tage_tables[t][tage_provider[t]][idx].ctr > 3'b000)
          tage_tables[t][tage_provider[t]][idx].ctr <= tage_tables[t][tage_provider[t]][idx].ctr - 1;
      end

      // Update SC table
      begin
        logic [$clog2(SC_ENTRIES)-1:0] sc_idx;
        sc_idx = compute_index(update_pc, ghr[t], 0) ^
                 compute_index(update_pc, ghr[t], TAGE_TABLES-1);
        if (update_taken && sc_table[t][sc_idx] < 63)
          sc_table[t][sc_idx] <= sc_table[t][sc_idx] + 1;
        else if (!update_taken && sc_table[t][sc_idx] > -64)
          sc_table[t][sc_idx] <= sc_table[t][sc_idx] - 1;
      end

      // Update RAS
      if (update_is_call) begin
        ras[t][ras_ptr[t]] <= update_pc + 4;
        ras_ptr[t] <= ras_ptr[t] + 1;
      end else if (update_is_return) begin
        if (ras_ptr[t] > 0) ras_ptr[t] <= ras_ptr[t] - 1;
      end

      // Update ITA for indirect branches
      if (update_is_indirect) begin
        logic [$clog2(ITA_ENTRIES)-1:0] ita_idx;
        ita_idx = update_pc[$clog2(ITA_ENTRIES)+1:2];
        ita[t][ita_idx].target <= update_target;
        ita[t][ita_idx].tag    <= update_pc[13:2];
        ita[t][ita_idx].valid  <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Flush Handling
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (flush_valid) begin
      // Reset GHR for flushed thread (conservative)
      ghr[flush_tid] <= '0;
    end
  end

  assign bpu_ready = 1'b1;  // BPU is always ready (pipelined)

endmodule : ifu_bpu
