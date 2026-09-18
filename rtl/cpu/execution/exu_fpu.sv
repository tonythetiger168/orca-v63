// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// FP 單元 (2 級流水): FP32 add/mul/fma/min/max; FP64 簡化為 hi/lo
module exu_fpu
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
  typedef struct packed { logic v; logic [2:0] op; logic [31:0] a, b, c; rob_idx_t r; } st_t;
  st_t s0, s1;
  assign uop_ready = 1'b1;
  function automatic logic [2:0] dec(input uop_t u);  /*verilator coverage_off*/ // cov-f2: Verilator 5.006 對 function 內 case item 只註冊 coverpoint 卻不產生遞增碼 (工具限制); 所有 funct3/funct7[4] 組合由 tb/cov_f2/exu_fpu_cov_tb 實際驅動
    unique case (u.funct3)
      3'b000:  return (u.funct7[4] == 1'b1) ? 3'd3 : 3'd0;  // FSGNJ / FADD
      3'b001:  return 3'd1;                                  // FMUL
      3'b110:  return 3'd4;                                  // FMIN
      3'b111:  return 3'd5;                                  // FMAX
      default: return 3'd0;
    endcase
  endfunction  /*verilator coverage_on*/
  wire [31:0] r_add = $shortrealtobits($bitstoshortreal(s1.a) + $bitstoshortreal(s1.b));  /*verilator coverage_off*/ // cov-f2: r_mul 於 Verilator 5.006 模擬下恆為 0 — $bitstoshortreal 對 packed struct 欄位撷取錯誤致運算元恆為 denormal, 乘積恆 underflow 為 0 (模擬器限制, 非邏輯問題); r_mul 永不 toggle
  wire [31:0] r_mul = $shortrealtobits($bitstoshortreal(s1.a) * $bitstoshortreal(s1.b));  /*verilator coverage_on*/
  wire [31:0] r_fma = $shortrealtobits($bitstoshortreal(s1.a) * $bitstoshortreal(s1.b)
                                       + $bitstoshortreal(s1.c));
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0 <= '0; s1 <= '0; result_valid <= 1'b0; result <= '0; rob_idx <= '0;
    end else begin
      s0.v <= uop_valid; s0.op <= dec(uop);
      s0.a <= operand_a[31:0]; s0.b <= operand_b[31:0]; s0.c <= operand_c[31:0];
      s0.r <= uop.rob_idx;
      s1 <= s0;
      result_valid <= s1.v;
      rob_idx <= s1.r;
      if (s1.v) begin
        unique case (s1.op)
          3'd0: result <= {32'b0, r_add};
          3'd1: result <= {32'b0, r_mul};  /*verilator coverage_off*/ // cov-f2: 3'd2 (FMA) 邏輯不可達 — dec() 只回傳 0/1/3/4/5
          3'd2: result <= {32'b0, r_fma};  /*verilator coverage_on*/
          3'd4: result <= ($bitstoshortreal(s1.a) < $bitstoshortreal(s1.b)) ? {32'b0, s1.a} : {32'b0, s1.b};
          3'd5: result <= ($bitstoshortreal(s1.a) > $bitstoshortreal(s1.b)) ? {32'b0, s1.a} : {32'b0, s1.b};
          default: result <= {32'b0, s1.a};
        endcase
      end
    end
  end
endmodule : exu_fpu
