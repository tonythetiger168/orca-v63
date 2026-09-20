// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// L1 BTB: BTB_ENTRIES 4-way, 提供 target/型別, LRU 替換
module ifu_btb
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  xword_t pc_q,
  output logic hit,
  output xword_t target,
  output logic [1:0] btype,
  input  logic upd_valid,
  input  xword_t upd_pc,
  input  xword_t upd_target,
  input  logic [1:0] upd_type
);
  import orca_pkg::*;
  localparam int WAYS = 4, SETS = BTB_ENTRIES / WAYS;
  localparam int SW = $clog2(SETS);
  localparam int TAGW = XLEN - SW - 2;
  logic [TAGW-1:0] tag [SETS][WAYS];
  xword_t          tgt [SETS][WAYS];
  logic [1:0]      typ [SETS][WAYS];
  logic            vld [SETS][WAYS];
  logic [WAYS-1:0] lru [SETS];
  wire [SW-1:0]  set = pc_q[SW+1:2];
  wire [TAGW-1:0] tq = pc_q[XLEN-1:SW+2];
  always_comb begin
    hit = 1'b0; target = '0; btype = '0;
    for (int w = 0; w < WAYS; w++)
      if (vld[set][w] && tag[set][w] == tq) begin
        hit = 1'b1; target = tgt[set][w]; btype = typ[set][w];
      end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < SETS; s++) begin
        lru[s] <= '0;
        for (int w = 0; w < WAYS; w++) vld[s][w] <= 1'b0;
      end
    end else if (upd_valid) begin : upd
      automatic logic done = 1'b0;
      automatic int vw = 0;
      for (int w = 0; w < WAYS; w++)
        if (vld[upd_pc[SW+1:2]][w] && tag[upd_pc[SW+1:2]][w] == upd_pc[XLEN-1:SW+2]) begin
          tgt[upd_pc[SW+1:2]][w] <= upd_target;
          typ[upd_pc[SW+1:2]][w] <= upd_type;
          done = 1'b1;
        end
      if (!done) begin
        for (int w = 0; w < WAYS; w++) if (lru[upd_pc[SW+1:2]][w] == 1'b0) vw = w;
        vld[upd_pc[SW+1:2]][vw] <= 1'b1;
        tag[upd_pc[SW+1:2]][vw] <= upd_pc[XLEN-1:SW+2];
        tgt[upd_pc[SW+1:2]][vw] <= upd_target;
        typ[upd_pc[SW+1:2]][vw] <= upd_type;
        lru[upd_pc[SW+1:2]] <= '0;
        lru[upd_pc[SW+1:2]][vw] <= 1'b1;
      end
    end
  end
endmodule : ifu_btb
