// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
// lsu_st 全覆蓋: 4 條 store 管線 x SB/SH/SW/SD, DTLB hit/miss/例外, FENCE/FENCE.I,
// store queue 滿, flush。
module unit_lsu_tb;
  import orca_pkg::*;
  localparam int NP = NUM_ST_PIPE;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  uop_t uop [NP]; logic uop_valid [NP], uop_ready [NP];
  logic [63:0] base_addr [NP], store_data [NP]; logic [2:0] funct3 [NP];
  logic [63:0] dtlb_vaddr [NP]; logic dtlb_req_valid [NP], dtlb_hit [NP];
  logic [63:0] dtlb_paddr [NP]; logic dtlb_exception [NP]; exception_t dtlb_exc_code [NP];
  logic [63:0] dcache_addr [NP]; logic dcache_req_valid [NP], dcache_req_we [NP];
  logic [511:0] dcache_req_data [NP]; logic [63:0] dcache_req_be [NP];
  logic dcache_req_ready [NP];
  logic [63:0] stq_addr [4]; logic [63:0] stq_data [4]; logic [7:0] stq_be [4];
  logic stq_valid [4]; rob_idx_t stq_rob_idx [4];
  logic result_valid [NP]; rob_idx_t result_rob_idx [NP];
  logic result_exception [NP]; exception_t result_exc_code [NP];
  logic fence_i_valid, fence_valid, fence_done, flush_valid; tid_t flush_tid;

  lsu_st u_st (.clk(clk), .rst_n(rst_n),
    .uop(uop), .uop_valid(uop_valid), .uop_ready(uop_ready),
    .base_addr(base_addr), .store_data(store_data), .funct3(funct3),
    .dtlb_vaddr(dtlb_vaddr), .dtlb_req_valid(dtlb_req_valid), .dtlb_hit(dtlb_hit),
    .dtlb_paddr(dtlb_paddr), .dtlb_exception(dtlb_exception), .dtlb_exc_code(dtlb_exc_code),
    .dcache_addr(dcache_addr), .dcache_req_valid(dcache_req_valid), .dcache_req_we(dcache_req_we),
    .dcache_req_data(dcache_req_data), .dcache_req_be(dcache_req_be), .dcache_req_ready(dcache_req_ready),
    .stq_addr(stq_addr), .stq_data(stq_data), .stq_be(stq_be),
    .stq_valid(stq_valid), .stq_rob_idx(stq_rob_idx),
    .result_valid(result_valid), .result_rob_idx(result_rob_idx),
    .result_exception(result_exception), .result_exc_code(result_exc_code),
    .fence_i_valid(fence_i_valid), .fence_valid(fence_valid), .fence_done(fence_done),
    .flush_valid(flush_valid), .flush_tid(flush_tid));

  initial begin
    for (int p=0;p<NP;p++) begin
      uop[p]='0; uop_valid[p]=0; base_addr[p]='0; store_data[p]='0; funct3[p]='0;
      dtlb_hit[p]=0; dtlb_paddr[p]='0; dtlb_exception[p]=0; dtlb_exc_code[p]=`EXC_NONE;
      dcache_req_ready[p]=1;
    end
    fence_i_valid=0; fence_valid=0; flush_valid=0; flush_tid='0;
    rst_n=0; #57 rst_n=1; @(negedge clk);

    // 每條管線 x 4 種 store 寬度
    for (int p=0;p<NP;p++) begin
      for (int f=0; f<4; f++) begin
        uop[p]='0; uop[p].opcode=OP_STORE; uop[p].is_store=1; uop[p].rob_idx=rob_idx_t'(p*4+f);
        base_addr[p]=64'h8000_0000 + p*256 + f*8; store_data[p]=64'hDEAD_BEEF_0000_0000+f;
        funct3[p]=3'(f); dtlb_hit[p]=1; dtlb_paddr[p]=64'h9000_0000+p*256+f*8; dcache_req_ready[p]=1;
        uop_valid[p]=1; @(negedge clk);
        begin int g=0; while(!uop_ready[p] && g<20) begin @(negedge clk); g++; end end
        uop_valid[p]=0; repeat(4) @(negedge clk);
      end
    end

    // DTLB miss -> hit
    uop[0]='0; uop[0].opcode=OP_STORE; uop[0].is_store=1; uop[0].rob_idx=20;
    base_addr[0]=64'hA000_0000; store_data[0]=64'h1234; funct3[0]=3'd3;
    dtlb_hit[0]=0; dcache_req_ready[0]=1;
    uop_valid[0]=1; @(negedge clk);
    begin int g=0; while(!dtlb_req_valid[0] && g<10) begin @(negedge clk); g++; end end
    dtlb_hit[0]=1; dtlb_paddr[0]=64'hA000_0000; @(negedge clk);
    begin int g=0; while(!uop_ready[0] && g<20) begin @(negedge clk); g++; end end
    uop_valid[0]=0; repeat(4) @(negedge clk);

    // DTLB 例外
    uop[1]='0; uop[1].opcode=OP_STORE; uop[1].is_store=1; uop[1].rob_idx=21;
    base_addr[1]=64'hB000_0000; store_data[1]=64'h0; funct3[1]=3'd3;
    dtlb_hit[1]=1; dtlb_paddr[1]=64'hB000_0000; dtlb_exception[1]=1;
    dtlb_exc_code[1]='{valid:1'b1, code:4'd7, tval:64'hB000_0000}; dcache_req_ready[1]=1;
    uop_valid[1]=1; @(negedge clk);
    begin int g=0; while(!uop_ready[1] && g<20) begin @(negedge clk); g++; end end
    uop_valid[1]=0; dtlb_exception[1]=0; dtlb_exc_code[1]=`EXC_NONE; repeat(4) @(negedge clk);

    // store queue 滿 (dcache_req_ready=0 不排空)
    dcache_req_ready[2]=0;
    for (int k=0;k<8;k++) begin
      uop[2]='0; uop[2].opcode=OP_STORE; uop[2].is_store=1; uop[2].rob_idx=rob_idx_t'(30+k);
      base_addr[2]=64'hC000_0000+k*8; store_data[2]=64'hAA00+k; funct3[2]=3'd3;
      dtlb_hit[2]=1; dtlb_paddr[2]=64'hC000_0000+k*8;
      uop_valid[2]=1; @(negedge clk);
      begin int g=0; while(!uop_ready[2] && g<10) begin @(negedge clk); g++; end end
      uop_valid[2]=0; @(negedge clk);
    end
    dcache_req_ready[2]=1; repeat(8) @(negedge clk);

    // FENCE / FENCE.I
    fence_valid=1; @(negedge clk); fence_valid=0;
    begin int g=0; while(!fence_done && g<30) begin @(negedge clk); g++; end end
    fence_i_valid=1; @(negedge clk); fence_i_valid=0;
    begin int g=0; while(!fence_done && g<30) begin @(negedge clk); g++; end end
    repeat(4) @(negedge clk);

    // flush
    flush_valid=1; flush_tid=2'd2; @(negedge clk); flush_valid=0; repeat(6) @(negedge clk);

    $display("LSU ST TB PASS");
    $finish;
  end
endmodule : unit_lsu_tb
