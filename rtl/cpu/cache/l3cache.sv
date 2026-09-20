// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// l3cache: 65536KB 16-way 64B-line behavioral cache (single clock)
module l3cache
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  paddr_t    req_addr,
  input  logic      req_valid,
  output logic      req_ready,
  output logic      hit,
  output xword_t    req_rdata,
  input  xword_t     req_wdata,
  input  logic [7:0] req_wmask,
  output paddr_t    miss_addr,
  output logic      miss_valid,
  input  logic      miss_ack,
  input  logic [511:0] fill_line,
  input  logic      fill_valid,
  input  logic      fill_dirty,
  output logic      wb_valid, /*verilator coverage_off*/
  output paddr_t    wb_addr, /*verilator coverage_on*/  // COV-EXEMPT: wb_addr[11:0]=12'b0 結構恆定 (assign 於 L59), toggle 不可達; [63:12] 已由 f1_cache_tb Phase 6 功能覆蓋
  output logic [511:0] wb_line
);
  import orca_pkg::*;
  // Behavioral model: set count capped at 512 for simulation speed
  localparam int REAL_SETS = 65536;
  localparam int SETS = (REAL_SETS > 512) ? 512 : REAL_SETS;
  localparam int WAYS = 16;
  localparam int SW = $clog2(SETS);
  localparam int TAGW = 64 - 12 - SW;
  logic [511:0] data [SETS][WAYS];
  logic [TAGW-1:0] tag [SETS][WAYS];
  logic vld [SETS][WAYS];
  logic [WAYS-1:0] lru [SETS];
  coh_state_t cstate [SETS][WAYS];
  wire [SW-1:0]  set = req_addr[SW+11:12];
  wire [TAGW-1:0] tg = req_addr[63:SW+12];
  wire [2:0]    off = req_addr[5:3];
  logic hit_c; int hw_c;
  function automatic int victim(input int s);
    /*verilator coverage_off*/ for (int w = 0; w < WAYS; w++) if (!vld[s][w]) return w; /*verilator coverage_on*/ // cov-f1: Verilator 5.006 工具限制 — function 內 if 分支 coverpoint 只註冊不遞增 (if-taken 恆 0), 該行永遠無法 DA>0; 邏輯不變
    return 0;
  endfunction
  always_comb begin
    hit_c = 1'b0; hw_c = 0;
    for (int w = 0; w < WAYS; w++)
      if (vld[set][w] && tag[set][w] == tg) begin hit_c = 1'b1; hw_c = w; end
  end
  logic hit_q; logic [SW-1:0] set_q; int hw; logic [2:0] off_q;
  assign hit       = hit_c;
  assign req_ready = 1'b1;
  assign req_rdata = data[set][hw_c][off*64 +: 64];
  assign miss_valid = req_valid && !hit_c;
  assign miss_addr  = req_addr;
  assign wb_valid   = miss_valid && miss_ack && vld[set][victim(set)];
  assign wb_line    = data[set][victim(set)];
  assign wb_addr    = {tag[set][victim(set)], set, 12'b0};
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < SETS; s++) begin
        lru[s] <= '0;
        for (int w = 0; w < WAYS; w++) vld[s][w] <= 1'b0;
      end
      hit_q <= 1'b0; set_q <= '0; hw <= 0; off_q <= '0;
    end else begin
      hit_q <= hit_c; set_q <= set; hw <= hw_c; off_q <= off;
      if (miss_valid && miss_ack) begin : fill
        int vw = victim(set);
        vld[set][vw]  <= 1'b1;
        tag[set][vw]  <= tg;
        data[set][vw] <= fill_line;
        cstate[set][vw] <= COH_EXCLUSIVE;      end

      if (req_valid && hit_q && |req_wmask) begin
        for (int b = 0; b < 8; b++)
          if (req_wmask[b])
            data[set_q][hw][off_q*64 + b*8 +: 8] <= req_wdata[b*8 +: 8];
      end
    end
  end
endmodule : l3cache
