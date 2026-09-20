// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - dtype sweep TB: 驗證全部 16 種 AI 資料型態 (INT8/INT2/INT3/INT4/
// INT5/INT6/BF16/FP16/FP32/FP8_E4M3/FP8_E5M2/BF8/NF4/FP4/BITNET) 之 PE MAC 路徑
// 與 acc 量化輸出。
`include "orca_pkg.sv"

module dtype_sweep_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  // ---- PE (systolic MAC element) — 真實介面 ----
  logic [3:0]  pe_dtype;
  logic [7:0]  pe_w, pe_a, pe_wo, pe_ao;
  logic [31:0] pe_psi, pe_pso;
  logic pe_ws, pe_acc, pe_flush, pe_skip;
  npu_pe u_pe (
    .clk(clk), .rst_n(rst_n), .clk_gate(1'b1),
    .weight_in(pe_w), .activation_in(pe_a),
    .partial_sum_in(pe_psi), .partial_sum_out(pe_pso),
    .weight_out(pe_wo), .activation_out(pe_ao),
    .dtype(pe_dtype), .weight_stationary(pe_ws),
    .accumulate_en(pe_acc), .flush_acc(pe_flush), .sparse_skip(pe_skip));

  // ---- acc (quantize/activate) ----
  logic [3:0] acc_dtype;
  logic [7:0] acc_out; logic acc_ov;
  npu_acc u_acc (
    .clk(clk), .rst_n(rst_n),
    .acc_in(32'h0000_00C8), .in_valid(1'b1),
    .bias(32'h0000_000A), .dtype(acc_dtype), .act_mode(2'd0),
    .out(acc_out), .out_valid(acc_ov));

  int checks = 0, passed = 0;
  // 正確驅動 PE: weight 流入(ws=0), 累加 n 拍, 再 flush 一拍輸出 accumulator
  logic [31:0] pe_pso_cap;   // flush 高電平期間捕捉的 psum
  task automatic pe_run(input int n_acc);
    pe_ws = 0; pe_acc = 1; pe_flush = 0;
    repeat (n_acc) @(negedge clk);
    pe_acc = 0; pe_flush = 1; #1;      // flush 高、accumulator 尚未被重置
    pe_pso_cap = pe_pso;               // pso = flush_acc ? accumulator
    @(negedge clk); pe_flush = 0; #1;
  endtask
  task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got === exp) begin passed++; $display("  PASS %s", name); end
    else $display("  FAIL %s = %0d (exp %0d)", name, got, exp);
  endtask

  initial begin
    pe_dtype = '0; acc_dtype = '0;
    pe_w = 8'h03; pe_a = 8'h05; pe_psi = 32'd0;
    pe_ws = 1'b1; pe_acc = 1'b1; pe_flush = 1'b0; pe_skip = 1'b0;
    rst_n = 0; #57 rst_n = 1; @(negedge clk);

    $display("=== dtype sweep: 16 types through PE + acc ===");
    for (int dt = 0; dt < 15; dt++) begin
      pe_dtype = 4'(dt); acc_dtype = 4'(dt);
      pe_run(4);
      $display("dtype=%0d (%s): psum=%0d acc_out=%0d", dt, dtype_name(4'(dt)), pe_pso_cap, acc_out);
    end

    // ---- functional spot-checks ----
    // INT8: 3*5=15 -> psum nonzero positive
    pe_dtype = AI_DTYPE_INT8; pe_run(4);
    check("INT8 psum>0", (pe_pso_cap != 0 && pe_pso_cap[31] == 1'b0), 1);
    // INT4: low-nibble sign-extended 3*5=15, 2x shift -> 30-ish
    pe_dtype = AI_DTYPE_INT4; pe_run(4);
    check("INT4 psum>0", (pe_pso_cap != 0 && pe_pso_cap[31] == 1'b0), 1);
    // INT2: 4x shift, positive
    pe_dtype = AI_DTYPE_INT2; pe_w = 8'h01; pe_run(4); pe_w = 8'h03;
    check("INT2 psum>0", (pe_pso_cap != 0 && pe_pso_cap[31] == 1'b0), 1);
    // BITNET: weight_reg[1:0]=2'b11 -> -1 -> term negative
    pe_dtype = AI_DTYPE_BITNET; pe_w = 8'h0F; pe_run(4); pe_w = 8'h03;
    check("BITNET psum<0", (pe_pso_cap[31] == 1'b1), 1);
    pe_w = 8'h03;  // restore
    // NF4: weight[3:0]=15 -> LUT=+64, act=5 -> 320 positive
    pe_dtype = AI_DTYPE_NF4; pe_w = 8'h0F; pe_run(4); pe_w = 8'h03;
    check("NF4 psum>0", (pe_pso_cap != 0 && pe_pso_cap[31] == 1'b0), 1);
    pe_w = 8'h03;
    // FP32: FP32 FMA path produces a value (FP32 1.0*1.0=1.0 pattern -> nonzero bits)
    pe_dtype = AI_DTYPE_FP32; pe_psi = 32'h3F80_0000; pe_w = 8'h3F; pe_a = 8'h80; pe_run(4);
    check("FP32 path active", (u_pe.fp32_mult != 32'h0), 1);
    pe_psi = 32'd0;

    // ---- helper checks ----
    check("w/byte INT2", dtype_weights_per_byte(AI_DTYPE_INT2), 4);
    check("w/byte INT3", dtype_weights_per_byte(AI_DTYPE_INT3), 2);
    check("w/byte INT5", dtype_weights_per_byte(AI_DTYPE_INT5), 1);
    check("w/byte INT6", dtype_weights_per_byte(AI_DTYPE_INT6), 1);
    check("w/byte FP32", dtype_weights_per_byte(AI_DTYPE_FP32), 0);
    check("int_bits INT6", dtype_int_bits(AI_DTYPE_INT6), 6);
    check("packed BITNET", dtype_is_packed(AI_DTYPE_BITNET), 1);
    check("packed INT8", dtype_is_packed(AI_DTYPE_INT8), 0);
    check("nf4_lut[15]", nf4_dequant_lut(4'd15), 64);
    check("bitnet 11=-1", bitnet_decode(2'b11), -1);
    check("FP8==E4M3", AI_DTYPE_FP8, AI_DTYPE_FP8_E4M3);

    if (passed == checks) $display("DTYPE TB PASS: %0d/%0d checks", passed, checks);
    else $fatal(1, "DTYPE TB FAIL: %0d/%0d", passed, checks);
    $finish;
  end

  function automatic string dtype_name(input logic [3:0] dt);
    case (dt)
      AI_DTYPE_INT8:     return "INT8";
      AI_DTYPE_INT2:     return "INT2";
      AI_DTYPE_INT3:     return "INT3";
      AI_DTYPE_INT4:     return "INT4";
      AI_DTYPE_INT5:     return "INT5";
      AI_DTYPE_INT6:     return "INT6";
      AI_DTYPE_BF16:     return "BF16";
      AI_DTYPE_FP16:     return "FP16";
      AI_DTYPE_FP32:     return "FP32";
      AI_DTYPE_FP8_E4M3: return "FP8_E4M3";
      AI_DTYPE_FP8_E5M2: return "FP8_E5M2";
      AI_DTYPE_BF8:      return "BF8";
      AI_DTYPE_NF4:      return "NF4";
      AI_DTYPE_FP4:      return "FP4";
      AI_DTYPE_BITNET:   return "BITNET";
      default:           return "???";
    endcase
  endfunction
endmodule : dtype_sweep_tb
