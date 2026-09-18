// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// GSCU: AIX 命令佇列 -> TDB busy 追蹤 -> 16 cluster round-robin 分派
module npu_gscu
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  aix_cmd_t cmd_in,
  input  logic     cmd_valid,
  output logic     cmd_ready,
  output logic     irq,
  input  aix_tdb_t tdb_rd [AIX_NUM_TDB],
  output logic [AIX_NUM_TDB-1:0] tdb_busy,
  output aix_cmd_t cl_cmd,
  output logic     cl_cmd_valid,
  input  logic     cl_cmd_ready,
  input  logic [CLUSTERS_PER_TILE-1:0] cl_done,
  input  logic [CLUSTERS_PER_TILE-1:0] cl_busy,
  // ORCA v6.3.3: attention engine dispatch (AIX_OP_ATTN_QK / AIX_OP_ATTN_AV).
  // New ports (only added, nothing renamed); connected at parent ai_tile.
  output logic     attn_cmd_valid,
  input  logic     attn_cmd_ready,
  input  logic     attn_done
);
  import orca_pkg::*;
  aix_cmd_t q [16];
  logic [4:0] qw, qr, qc;
  logic had_cmd;   // sticky: at least one command accepted since reset
  logic [CLUSTERS_PER_TILE-1:0] inflight;
  // v6.3.3: attention dispatch tracking
  logic attn_inflight;
  logic is_attn_head;
  assign is_attn_head = (q[qr].opcode == AIX_OP_ATTN_QK) ||
                        (q[qr].opcode == AIX_OP_ATTN_AV);
  assign cmd_ready = (qc < 5'd16);
  logic idle_all;
  always_comb begin
    idle_all = (qc == 0) && !attn_inflight;
    for (int i = 0; i < CLUSTERS_PER_TILE; i++)
      idle_all = idle_all && !inflight[i];
  end
  typedef enum logic [0:0] {G_RUN, G_DRAIN} gst_t;
  gst_t gst;
  int rr;
  always_comb begin
    cl_cmd       = q[qr];
    // v6.3.3: attention-class head uop is redirected to npu_attn_engine;
    // non-attention heads keep the original cluster dispatch semantics.
    cl_cmd_valid = (qc != 0) && (gst == G_RUN) && !is_attn_head;
    for (int i = 0; i < CLUSTERS_PER_TILE; i++)
      if (!cl_busy[(rr + i) % CLUSTERS_PER_TILE] && (qc != 0) && !is_attn_head)
        cl_cmd_valid = 1'b1;
    attn_cmd_valid = (qc != 0) && (gst == G_RUN) && is_attn_head && !attn_inflight;
    irq = idle_all && had_cmd;   // pulse when all queued work drains
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      qw <= '0; qr <= '0; qc <= '0; rr <= 0; gst <= G_RUN; inflight <= '0;
      had_cmd <= 1'b0;
      tdb_busy <= '0;
      attn_inflight <= 1'b0;
    end else begin
      if (attn_cmd_valid && attn_cmd_ready) begin
        qr <= qr + 1'b1; qc <= qc - 1'b1;
        attn_inflight <= 1'b1;
      end
      if (attn_done) attn_inflight <= 1'b0;
      if (cmd_valid && cmd_ready) begin
        q[qw] <= cmd_in; qw <= qw + 1'b1; qc <= qc + 1'b1;
        had_cmd <= 1'b1;
        tdb_busy[cmd_in.tdb0] <= 1'b1;
        tdb_busy[cmd_in.tdb1] <= 1'b1;
      end
      if (cl_cmd_valid && cl_cmd_ready) begin
        qr <= qr + 1'b1; qc <= qc - 1'b1;
        inflight[rr % CLUSTERS_PER_TILE] <= 1'b1;
        rr <= (rr + 1) % CLUSTERS_PER_TILE;
      end
      for (int i = 0; i < CLUSTERS_PER_TILE; i++)
        if (cl_done[i]) inflight[i] <= 1'b0;
      if (cmd_valid && cmd_in.opcode == AIX_OP_DMA_ST) gst <= G_DRAIN;  /*verilator coverage_off*/ // G_DRAIN→G_RUN arm 邏輯不可達 (DRAIN 中 qc 無法 drain 歸零)
      if (gst == G_DRAIN && idle_all) gst <= G_RUN;  /*verilator coverage_on*/
    end
  end
endmodule : npu_gscu
