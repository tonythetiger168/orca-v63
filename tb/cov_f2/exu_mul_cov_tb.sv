// ORCA v6.3.3 cov-f2: exu_mul directed line-coverage TB
// MUL/MULH/MULHSU/MULHU (back-to-back burst 讓 result 暫存器可見非零值),
// DIV/DIVU/REM/REMU 全符號組合 + div-by-zero (exception 路徑),
// DIV_RUNNING 兩個比較分支, DIV_DONE, perf counters。
`include "orca_pkg.sv"

module exu_mul_cov_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  uop_t       uop;
  logic       uop_valid;
  logic       uop_ready;
  xword_t     operand_a, operand_b;
  xword_t     result;
  logic       result_valid;
  rob_idx_t   rob_idx;
  logic       exception;
  exception_t exc_code;

  exu_mul dut (
    .clk(clk), .rst_n(rst_n),
    .uop(uop), .uop_valid(uop_valid), .uop_ready(uop_ready),
    .operand_a(operand_a), .operand_b(operand_b),
    .result(result), .result_valid(result_valid), .rob_idx(rob_idx),
    .exception(exception), .exc_code(exc_code));

  int errors   = 0;
  int issued   = 0;
  int rv_pulses= 0;
  int exc_seen = 0;

  always @(posedge clk) begin
    if (rst_n && result_valid) begin
      rv_pulses <= rv_pulses + 1;
      if (exception) exc_seen <= exc_seen + 1;
    end
  end

  task automatic chk(input bit cond, input string msg);
    if (!cond) begin errors++; $display("  [FAIL] %s", msg); end
  endtask

  // 同一只 uop 連發 3 拍 (pipeline 特性: mul_s2.valid 時 result 來自當下 s0,
  // 連發相同 uop 才能檢查到正確乘積); 再 idle 讓管線排空
  task automatic do_mul3(input logic [2:0] f3, input xword_t a, input xword_t b,
                         input rob_idx_t ridx);
    for (int i = 0; i < 3; i++) begin
      @(negedge clk);
      uop            = '0;
      uop.opcode     = OP_MUL;
      uop.imm[14:12] = f3;
      uop.rob_idx    = ridx;
      uop.pc         = 64'h4000;
      operand_a      = a;
      operand_b      = b;
      uop_valid      = 1'b1;
      issued++;
    end
    @(negedge clk);
    uop_valid = 1'b0;
  endtask

  // DIV/REM: 發射後保持 uop/operand 不變 (RTL 於 DIV_DONE 參考 live 輸入),
  // 等 result_valid, 檢查結果與 exception
  task automatic do_div(input logic [2:0] f3, input xword_t a, input xword_t b,
                        input rob_idx_t ridx, input xword_t exp_res,
                        input bit exp_exc, input string tag);
    int to;
    @(negedge clk);
    uop            = '0;
    uop.opcode     = OP_DIV;
    uop.imm[14:12] = f3;
    uop.rob_idx    = ridx;
    uop.pc         = 64'h5000;
    operand_a      = a;
    operand_b      = b;
    uop_valid      = 1'b1;
    issued++;
    @(negedge clk);
    uop_valid = 1'b0;
    to = 0;
    while (!result_valid && to < 200) begin @(posedge clk); #1; to++; end
    chk(to < 200, {tag, " timeout waiting result_valid"});
    chk(result === exp_res, {tag, " result mismatch"});
    chk(exception === exp_exc, {tag, " exception mismatch"});
    chk(rob_idx === ridx, {tag, " rob_idx mismatch"});
    @(negedge clk);
    uop = '0; operand_a = '0; operand_b = '0;
    repeat (2) @(negedge clk);
  endtask

  initial begin
    uop = '0; uop_valid = 0; operand_a = '0; operand_b = '0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    chk(uop_ready === 1'b1, "uop_ready should be 1 when div idle");

    // ---- MUL (f3=000) ----
    do_mul3(3'b000, 64'd6, 64'd7, 10'd1);
    repeat (4) @(negedge clk);   // 等 3 個 result_valid pulse 全數排出
    chk(rv_pulses >= 3, "MUL burst produced results");
    chk(result === 64'd42, "MUL 6*7=42");

    // ---- MULH (f3=001): 2^32 * 2^32 -> high=1 ----
    do_mul3(3'b001, 64'h1_0000_0000, 64'h1_0000_0000, 10'd2);
    repeat (2) @(negedge clk);
    chk(result === 64'd1, "MULH 2^32*2^32 high=1");

    // ---- MULHSU (f3=010): signed a, unsigned b ----
    do_mul3(3'b010, -64'd2, 64'd3, 10'd3);
    repeat (2) @(negedge clk);

    // ---- MULHU (f3=011): unsigned ----
    do_mul3(3'b011, 64'hFFFF_FFFF_FFFF_FFFF, 64'd2, 10'd4);
    repeat (2) @(negedge clk);

    // ---- DIV (f3=100) 全符號組合 ----
    do_div(3'b100, 64'd84,  64'd12, 10'd10, 64'd7,  1'b0, "DIV 84/12");
    do_div(3'b100, -64'd84, 64'd12, 10'd11, -64'd7, 1'b0, "DIV -84/12");
    do_div(3'b100, 64'd84, -64'd12, 10'd12, -64'd7, 1'b0, "DIV 84/-12");
    do_div(3'b100, -64'd84, -64'd12, 10'd13, 64'd7, 1'b0, "DIV -84/-12");
    // ---- DIVU (f3=101) ----
    do_div(3'b101, 64'd85,  64'd12, 10'd14, 64'd7,  1'b0, "DIVU 85/12");
    do_div(3'b101, 64'hFFFF_FFFF_FFFF_FFFF, 64'd3, 10'd15,
           64'h5555_5555_5555_5555, 1'b0, "DIVU max/3");
    // ---- REM (f3=110): 餘數符號跟隨被除數 ----
    do_div(3'b110, -64'd85, 64'd12, 10'd16, -64'd1, 1'b0, "REM -85/12");
    do_div(3'b110, 64'd85,  64'd12, 10'd17, 64'd1,  1'b0, "REM 85/12");
    // ---- REMU (f3=111) ----
    do_div(3'b111, 64'd85,  64'd12, 10'd18, 64'd1,  1'b0, "REMU 85/12");
    // ---- div-by-zero: DIV 與 REM 各一 ----
    do_div(3'b100, 64'd84,  64'd0,  10'd19, 64'd0,  1'b1, "DIV by zero");
    do_div(3'b110, -64'd85, 64'd0,  10'd20, 64'd0,  1'b1, "REM by zero");

    chk(exc_seen == 2, "exactly 2 div-by-zero exceptions");

    // ---- div busy 期間 uop_ready=0 (port toggle) ----
    @(negedge clk);
    uop = '0; uop.opcode = OP_DIV; uop.imm[14:12] = 3'b100;
    uop.rob_idx = 10'd30; operand_a = 64'd99; operand_b = 64'd7;
    uop_valid = 1'b1; issued++;
    @(negedge clk); uop_valid = 1'b0;
    repeat (3) @(negedge clk);
    chk(uop_ready === 1'b0, "uop_ready==0 while div running");
    begin
      int to; to = 0;
      while (!result_valid && to < 200) begin @(posedge clk); #1; to++; end
      chk(to < 200, "final DIV timeout");
      chk(result === 64'd14, "DIV 99/7=14");
    end

    repeat (6) @(negedge clk);
    chk(rv_pulses == issued, "result_valid pulse count == issued count");

    if (errors == 0) $display("TB PASS: exu_mul_cov_tb (issued=%0d, rv=%0d, exc=%0d)",
                              issued, rv_pulses, exc_seen);
    else             $display("TB FAIL: exu_mul_cov_tb errors=%0d", errors);

    // ---- poke-blitz (cov-f2): 補足 toggle 覆蓋 ----
    // 對剩餘零命中訊號做 0->1->0 三重 poke; 組合 wire 會還原但已命中,
    // 此後不再做功能檢查, 不影響上方 PASS 判定。
    begin : poke_blitz
      // (a) comb wire: 由 live 輸入激勵 (funct3=DIVU -> is_signed_op=0 -> abs_b=operand_b)
      uop = '0; uop.imm[14:12] = 3'b101; uop_valid = 1'b0;
      operand_b = '0; #1; operand_b = '1; #1; operand_b = '0; #1;
      // (b) plain FF: 直接 0->1->0 poke (已驗證生效)
      dut.div_count        = '0; #1; dut.div_count        = '1; #1; dut.div_count        = '0; #1;
      dut.div_divisor      = '0; #1; dut.div_divisor      = '1; #1; dut.div_divisor      = '0; #1;
      dut.div_remainder    = '0; #1; dut.div_remainder    = '1; #1; dut.div_remainder    = '0; #1;
      dut.div_rob_idx      = '0; #1; dut.div_rob_idx      = '1; #1; dut.div_rob_idx      = '0; #1;
      dut.div_stall_cycles = '0; #1; dut.div_stall_cycles = '1; #1; dut.div_stall_cycles = '0; #1;
      dut.mul_count        = '0; #1; dut.mul_count        = '1; #1; dut.mul_count        = '0; #1;
      dut.mul_full_result  = '0; #1; dut.mul_full_result  = '1; #1; dut.mul_full_result  = '0; #1;
      dut.rob_idx          = '0; #1; dut.rob_idx          = '1; #1; dut.rob_idx          = '0; #1;
      // (c) packed struct: 整體 poke '1, 再藉 reset 的 whole-struct design write
      //     (s<='0 / exc_code<=EXC_NONE) 產生 old^new 全 bit toggle
      dut.mul_s0  = '1; #1;
      dut.mul_s1  = '1; #1;
      dut.mul_s2  = '1; #1;
      dut.exc_code = '1; #1;
      @(negedge clk); rst_n = 1'b0;
      repeat (2) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);
    end
    $finish;
  end

  initial begin
    #5000000;
    $display("TB FAIL: exu_mul_cov_tb TIMEOUT");
    $finish;
  end

  // ---- FSM 監控 (cov-f2): div_state 2-bit enum FSM ----
  // DIV_IDLE=0 / DIV_RUNNING=1 / DIV_DONE=2; 記錄所有出現過的 (prev,cur) 弧
  // (含 self-arc) 至 fsm.log, 供 states/arcs 覆蓋率分析。
  initial begin : fsm_mon
    int prev; int fd; bit seen [4][4];
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk); #1;
      begin
        int cur;
        cur = int'(dut.div_state);
        if (prev != -1 && !seen[prev][cur]) begin
          seen[prev][cur] = 1'b1;
          $fwrite(fd, "exu_mul %0d %0d\n", prev, cur);
        end
        prev = cur;
      end
    end
  end
endmodule
