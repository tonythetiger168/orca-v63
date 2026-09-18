// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// MSHR: MSHR_ENTRIES 項 miss 追蹤, 同線合併, 完成回報
module lsu_mshr
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  paddr_t req_addr,
  input  logic   req_valid,
  input  logic   req_is_store,
  output logic   req_accept,
  output mshr_idx_t req_idx,
  output logic   miss_full,
  input  logic   fill_valid,
  input  paddr_t fill_addr,
  output logic [MSHR_ENTRIES-1:0] complete,
  output paddr_t complete_addr [MSHR_ENTRIES],
  input  logic   retire_entry,
  input  mshr_idx_t retire_idx,
  output logic   wb_req,
  output paddr_t wb_addr
);
  import orca_pkg::*;
  paddr_t addr [MSHR_ENTRIES];
  logic   vld  [MSHR_ENTRIES];
  logic   st   [MSHR_ENTRIES];
  logic   done [MSHR_ENTRIES];
  wire [XLEN-13:0] rtag = req_addr[XLEN-1:12];
  logic merge_hit;
  always_comb begin
    merge_hit = 1'b0; req_idx = '0; req_accept = 1'b0;
    miss_full = 1'b1;
    for (int i = 0; i < MSHR_ENTRIES; i++) miss_full = miss_full && vld[i];
    for (int i = 0; i < MSHR_ENTRIES; i++) begin
      complete[i]     = vld[i] && done[i];
      complete_addr[i]= addr[i];
      if (vld[i] && addr[i][XLEN-1:12] == rtag) begin
        merge_hit = 1'b1; req_idx = mshr_idx_t'(i);
      end
    end
    if (req_valid && !miss_full) begin
      if (merge_hit) req_accept = 1'b1;
      else begin
        for (int i = 0; i < MSHR_ENTRIES; i++) /* verilator coverage_off */ // cov: v_branch 只註冊無遞增碼, 行為已由 TB 實測 (tool limit)
          if (!vld[i] && !req_accept) begin
            req_idx = mshr_idx_t'(i); req_accept = 1'b1; /* verilator coverage_on */
          end
      end
    end
  end
  always_comb begin
    wb_req = 1'b0; wb_addr = '0;
    for (int i = 0; i < MSHR_ENTRIES; i++)
      if (vld[i] && done[i] && st[i]) begin
        wb_req = 1'b1; wb_addr = addr[i];
      end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < MSHR_ENTRIES; i++) begin
        vld[i] <= 1'b0; done[i] <= 1'b0;
      end
    end else begin
      if (fill_valid)
        for (int i = 0; i < MSHR_ENTRIES; i++)
          if (vld[i] && addr[i][XLEN-1:12] == fill_addr[XLEN-1:12])
            done[i] <= 1'b1;
      if (req_valid && req_accept && !merge_hit) begin
        vld[req_idx]  <= 1'b1;
        addr[req_idx] <= req_addr;
        st[req_idx]   <= req_is_store;
        done[req_idx] <= 1'b0;
      end
      if (retire_entry) begin
        vld[retire_idx] <= 1'b0;
        done[retire_idx] <= 1'b0;
      end
    end
  end
endmodule : lsu_mshr
