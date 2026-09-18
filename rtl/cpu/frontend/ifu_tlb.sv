// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// I-TLB: ITLB_ENTRIES 直接對映, Sv48 4K/2M/1G, refill port
module ifu_tlb
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  xword_t va,
  input  logic q_valid,
  output logic hit,
  output paddr_t pa,
  output logic miss,
  input  logic fill_valid,
  input  xword_t fill_va,
  input  paddr_t fill_pa,
  input  logic [1:0] fill_pagesz
);
  import orca_pkg::*;
  localparam int N = ITLB_ENTRIES, IW = $clog2(N);
  logic [43:0] vpn [N];
  paddr_t      ppn [N];
  logic [1:0]  psz [N];
  logic        vld [N];
  logic [IW-1:0] rplc;
  wire [43:0] qvpn = va[55:12];
  always_comb begin
    hit = 1'b0; pa = va;
    for (int i = 0; i < N; i++)
      if (vld[i] && qvpn[43 -: (psz[i] == 2'd2 ? 17 : psz[i] == 2'd1 ? 26 : 44)]
                       == vpn[i][43 -: (psz[i] == 2'd2 ? 17 : psz[i] == 2'd1 ? 26 : 44)]) begin : m
        automatic int sh = (psz[i] == 2'd2) ? 30 : (psz[i] == 2'd1) ? 21 : 12;
        pa  = {ppn[i][PLEN-1:sh], va[sh-1:0]};
        hit = 1'b1;
      end
    miss = q_valid && !hit;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < N; i++) vld[i] <= 1'b0;
      rplc <= '0;
    end else if (fill_valid) begin
      vpn[rplc] <= fill_va[55:12]; ppn[rplc] <= fill_pa;
      psz[rplc] <= fill_pagesz;    vld[rplc] <= 1'b1;
      rplc <= rplc + 1'b1;
    end
  end
endmodule : ifu_tlb
