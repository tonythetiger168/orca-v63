// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 解碼->分派緩衝: DECODE_WIDTH 入 / DISPATCH_WIDTH 出 flop FIFO
module idu_uop_queue
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t [DECODE_WIDTH-1:0]   in_uop,
  input  logic [DECODE_WIDTH-1:0]   in_valid,
  output logic [DECODE_WIDTH-1:0]   in_ready,
  output uop_t [DISPATCH_WIDTH-1:0] out_uop,
  output logic [DISPATCH_WIDTH-1:0] out_valid,
  input  logic [DISPATCH_WIDTH-1:0] out_ready,
  output logic [6:0] occupancy
);
  import orca_pkg::*;
  localparam int QD = 64, AW = 6;
  uop_t bufq [QD];
  logic [AW:0] wptr, rptr, cnt;
  wire can_accept = (cnt <= QD - DECODE_WIDTH);
  assign occupancy = cnt[6:0];
  always_comb begin
    for (int i = 0; i < DECODE_WIDTH; i++)   in_ready[i]  = can_accept;
    for (int i = 0; i < DISPATCH_WIDTH; i++) begin
      out_valid[i] = (cnt > i);
      out_uop[i]   = (cnt > i) ? bufq[(rptr + i[AW:0]) % QD] : `UOP_NOP;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin wptr <= '0; rptr <= '0; cnt <= '0; end
    else begin
      automatic int wi = 0, ri = 0;
      for (int i = 0; i < DECODE_WIDTH; i++)
        if (in_valid[i] && in_ready[i]) begin
          bufq[(wptr + wi[AW:0]) % QD] <= in_uop[i];
          wi = wi + 1;
        end
      for (int i = 0; i < DISPATCH_WIDTH; i++)
        if (out_valid[i] && out_ready[i]) ri = ri + 1;
      wptr <= wptr + wi[AW:0];
      rptr <= rptr + ri[AW:0];
      cnt  <= cnt + wi - ri;
    end
  end
endmodule : idu_uop_queue
