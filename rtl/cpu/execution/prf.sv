// ORCA v6.3 ZEN++ - v6.3.3
`include "orca_pkg.sv"

// 實體暫存器檔 (int): WPORTS 寫入 / RPORTS 組合讀取
module prf
  import orca_pkg::*;
#(
  parameter int WPORTS = 8,
  parameter int RPORTS = 10
)(
  input  logic clk, rst_n,
  input  phys_reg_idx_t [WPORTS-1:0] w_tag,
  input  xword_t        [WPORTS-1:0] w_data,
  input  logic          [WPORTS-1:0] w_valid,
  input  phys_reg_idx_t [RPORTS-1:0] r_tag,
  output xword_t        [RPORTS-1:0] r_data
);
  xword_t mem [INT_PRF_ENTRIES];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < INT_PRF_ENTRIES; i++) mem[i] <= '0;
    end else begin
      for (int i = 0; i < WPORTS; i++)
        if (w_valid[i]) mem[w_tag[i]] <= w_data[i];
    end
  end
  always_comb begin
    for (int i = 0; i < RPORTS; i++)
      r_data[i] = (r_tag[i] == 0) ? '0 : mem[r_tag[i]];
  end
endmodule : prf
