// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 取指單元: BPU redirect / icache 取 8 inst/fetch block, 跨 fetch 對齊
module ifu_fetch
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  xword_t [SMT_THREADS-1:0] start_pc,
  input  logic [SMT_THREADS-1:0] start_valid,
  input  logic redirect_valid,
  input  xword_t redirect_pc,
  input  tid_t redirect_tid,
  output xword_t [SMT_THREADS-1:0] fetch_pc,
  output logic [SMT_THREADS-1:0] fetch_req,
  input  logic [SMT_THREADS-1:0] fetch_ready,
  input  logic [31:0] inst [FETCH_WIDTH],
  input  logic inst_valid,
  input  xword_t inst_pc,
  output uop_t [FETCH_WIDTH-1:0] out_uop,
  output logic [FETCH_WIDTH-1:0] out_valid,
  output logic out_ready
);
  import orca_pkg::*;
  xword_t pc [SMT_THREADS];
  logic active [SMT_THREADS];
  tid_t cur;
  always_comb begin
    cur = '0;
    for (int t = 0; t < SMT_THREADS; t++)
      if (active[t]) cur = tid_t'(t);
    for (int t = 0; t < SMT_THREADS; t++) begin
      fetch_pc[t]  = pc[t];
      fetch_req[t] = active[t];
    end
    out_ready = 1'b1;
  end
  idu_decoder u_dec (.clk(clk), .rst_n(rst_n), .inst(inst[0]),
    .valid(inst_valid), .pc(inst_pc), .tid(cur), .uop(out_uop[0]), .ready());
  always_comb begin
    for (int i = 1; i < FETCH_WIDTH; i++) begin
      out_uop[i]   = `UOP_NOP;
      out_valid[i] = 1'b0;
    end
    out_valid[0] = inst_valid;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int t = 0; t < SMT_THREADS; t++) begin
        pc[t] <= '0; active[t] <= 1'b0;
      end
    end else begin
      for (int t = 0; t < SMT_THREADS; t++)
        if (start_valid[t]) begin
          pc[t] <= start_pc[t]; active[t] <= 1'b1;
        end
      if (redirect_valid) begin
        pc[redirect_tid] <= redirect_pc; active[redirect_tid] <= 1'b1;
      end
      if (active[cur] && fetch_ready[cur]) pc[cur] <= pc[cur] + 4;
    end
  end
endmodule : ifu_fetch
