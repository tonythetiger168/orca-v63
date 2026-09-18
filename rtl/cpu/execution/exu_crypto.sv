// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// 加密單元 (Zk 子集): SHA256 Σ/σ/Ch/Maj + 32-bit CLMUL, 1 級流水
module exu_crypto
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  uop_t uop,
  input  logic uop_valid,
  output logic uop_ready,
  input  xword_t operand_a, operand_b, operand_c,
  output xword_t result,
  output logic result_valid,
  output rob_idx_t rob_idx
);
  import orca_pkg::*;
  function automatic logic [31:0] ror32(input logic [31:0] x, input int n);
    return (x >> n) | (x << (32 - n));
  endfunction
  logic [31:0] a, b, c, res_c;
  always_comb begin
    a = operand_a[31:0]; b = operand_b[31:0]; c = operand_c[31:0];
    unique case (uop.funct3)
      3'b000:  res_c = ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22);      // SHA256 Σ0
      3'b001:  res_c = ror32(a, 6) ^ ror32(a, 11) ^ ror32(a, 25);      // SHA256 Σ1
      3'b010:  res_c = ror32(a, 7) ^ ror32(a, 18) ^ (a >> 3);          // SHA256 σ0
      3'b011:  res_c = ror32(a, 17) ^ ror32(a, 19) ^ (a >> 10);        // SHA256 σ1
      3'b100:  res_c = (a & b) ^ (~a & c);                             // Ch
      3'b101:  res_c = (a & b) ^ (a & c) ^ (b & c);                    // Maj
      3'b110: begin                                                    // CLMUL
        res_c = '0;
        for (int i = 0; i < 32; i++) if (a[i]) res_c = res_c ^ (b << i);
      end
      default: res_c = a ^ b ^ c;
    endcase
  end
  assign uop_ready = 1'b1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin result_valid <= 1'b0; result <= '0; rob_idx <= '0; end
    else begin
      result_valid <= uop_valid;
      rob_idx      <= uop.rob_idx;
      result       <= {32'b0, res_c};
    end
  end
endmodule : exu_crypto
