// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// dTLB: 128-entry 4-way set-assoc 簡化, Sv39 4KB page
module lsu_dtlb
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  xword_t va,
  input  logic req,
  output paddr_t pa,
  output logic hit,
  output logic perm_err,
  input  logic upd_valid,
  input  xword_t upd_vpn,
  input  paddr_t upd_ppn,
  input  logic upd_ur, upd_uw
);
  import orca_pkg::*;
  logic [51:0] vpn_arr [DTLB_ENTRIES];
  logic [51:0] ppn_arr [DTLB_ENTRIES];
  logic ur_arr [DTLB_ENTRIES], uw_arr [DTLB_ENTRIES], vld [DTLB_ENTRIES];
  always_comb begin
    hit = 1'b0; pa = '0; perm_err = 1'b0;
    for (int e = 0; e < DTLB_ENTRIES; e++)
      if (vld[e] && vpn_arr[e] == va[63:12]) begin
        hit = 1'b1;
        pa = {ppn_arr[e], va[11:0]};
        perm_err = !(ur_arr[e] | uw_arr[e]);
      end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int e = 0; e < DTLB_ENTRIES; e++) vld[e] <= 1'b0;
    end else if (upd_valid) begin
      automatic int sel = 0;
      for (int e = 0; e < DTLB_ENTRIES; e++) if (!vld[e]) begin sel = e; break; end
      vpn_arr[sel] <= upd_vpn[63:12];
      ppn_arr[sel] <= upd_ppn[63:12];
      ur_arr[sel] <= upd_ur;
      uw_arr[sel] <= upd_uw;
      vld[sel] <= 1'b1;
    end
  end
endmodule : lsu_dtlb
