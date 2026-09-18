// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 取指單元: redirect 優先, 8-inst block FIFO, RVC 偵測
module ifu_fetch
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  logic redirect_valid,
  input  xword_t redirect_pc,
  output xword_t fetch_pc,
  output logic   fetch_req,
  input  logic   fetch_ack,
  input  logic [FETCH_WIDTH*32-1:0] fetch_block,
  output logic [FETCH_WIDTH*32-1:0] dec_block,
  output xword_t dec_pc,
  output logic [FETCH_WIDTH-1:0]    dec_rvc,
  output logic dec_valid,
  input  logic dec_ready,
  output logic [7:0] fetchbuf_cnt
);
  import orca_pkg::*;
  xword_t pc_r, pc_n;
  logic [FETCH_WIDTH*32-1:0] blk [8];
  xword_t blkpc [8];
  logic [3:0] blklen;
  wire push = fetch_ack && !(dec_valid && dec_ready);
  wire pop  = dec_valid && dec_ready;
  assign fetch_req = 1'b1;
  always_comb begin
    if (redirect_valid) pc_n = redirect_pc;
    else if (fetch_ack && !pop) pc_n = pc_r + FETCH_WIDTH*4;
    else pc_n = pc_r;
  end
  assign fetch_pc    = pc_n;
  assign dec_valid   = (blklen != 0);
  assign dec_block   = blk[0];
  assign dec_pc      = blkpc[0];
  assign fetchbuf_cnt = {blklen, 4'b0};
  always_comb begin
    for (int i = 0; i < FETCH_WIDTH; i++)
      dec_rvc[i] = ~blk[0][i*32+1];
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_r <= 64'h8000_0000; blklen <= '0;
      for (int i = 0; i < 8; i++) begin blk[i] <= '0; blkpc[i] <= '0; end
    end else begin
      pc_r <= pc_n;
      if (redirect_valid) blklen <= '0;
      else begin
        if (push) begin
          for (int i = 7; i > 0; i--) begin blk[i] <= blk[i-1]; blkpc[i] <= blkpc[i-1]; end
          blk[0] <= fetch_block; blkpc[0] <= pc_r;
        end else if (pop) begin
          for (int i = 0; i < 7; i++) begin blk[i] <= blk[i+1]; blkpc[i] <= blkpc[i+1]; end
          blk[7] <= '0; blkpc[7] <= '0;
        end
        blklen <= blklen + push - pop;
      end
    end
  end
endmodule : ifu_fetch
