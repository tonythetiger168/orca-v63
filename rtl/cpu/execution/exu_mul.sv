//=============================================================================
// ORCA v6.3 ZEN++ Multiply/Divide Execution Unit
// File: rtl/cpu/execution/exu_mul.sv
// Description: 64-bit integer multiplier and divider
//              MUL: 3-cycle latency, fully pipelined
//              DIV: 18-30 cycle latency, non-pipelined
//              Supports RV64M extension (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU)
//=============================================================================

`include "orca_pkg.sv"

module exu_mul
  import orca_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // Issue Interface
  input  uop_t        uop,
  input  logic        uop_valid,
  output logic        uop_ready,

  // Operand Interface
  input  xword_t      operand_a,      // rs1
  input  xword_t      operand_b,      // rs2

  // Result Interface
  output xword_t      result,
  output logic        result_valid,
  output rob_idx_t    rob_idx,

  // Exception
  output logic        exception,
  output exception_t  exc_code
);

  import orca_pkg::*;

  // v6.3.3: orca_pkg 未定義 EXC_ILLEGAL_INST (原引用會在實例化後造成
  // 未定義識別子錯誤); 契約禁止更動 orca_pkg type, 以本地常數取代
  localparam exception_t EXC_ILLEGAL_INST = '{valid: 1'b1, code: 4'd2, tval: 64'b0};

  // ---------------------------------------------------------------------------
  // Instruction Decode
  // ---------------------------------------------------------------------------
  logic [2:0] funct3;
  logic       is_mul;       // MUL, MULH, MULHSU, MULHU
  logic       is_div;       // DIV, DIVU
  logic       is_rem;       // REM, REMU
  logic       is_signed_op;
  logic       is_high_result;  // MULH, MULHSU, MULHU (upper 64 bits)

  assign funct3 = uop.imm[14:12];

  always_comb begin
    is_mul = 1'b0;
    is_div = 1'b0;
    is_rem = 1'b0;
    is_signed_op = 1'b0;
    is_high_result = 1'b0;

    case (funct3)
      3'b000: begin is_mul = 1'b1; is_signed_op = 1'b1; end                    // MUL
      3'b001: begin is_mul = 1'b1; is_signed_op = 1'b1; is_high_result = 1'b1; end // MULH
      3'b010: begin is_mul = 1'b1; is_signed_op = 1'b1; is_high_result = 1'b1; end // MULHSU
      3'b011: begin is_mul = 1'b1; is_high_result = 1'b1; end                  // MULHU
      3'b100: begin is_div = 1'b1; is_signed_op = 1'b1; end                    // DIV
      3'b101: begin is_div = 1'b1; end                                         // DIVU
      3'b110: begin is_rem = 1'b1; is_signed_op = 1'b1; end                    // REM
      3'b111: begin is_rem = 1'b1; end                                         // REMU
    endcase
  end

  // ---------------------------------------------------------------------------
  // Multiplier (3-cycle pipelined Wallace Tree)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [63:0] op_a;
    logic [63:0] op_b;
    logic        is_high;
    logic        is_signed_a;
    logic        is_signed_b;
    rob_idx_t    rob_idx;
    logic [2:0]  funct3;
  } mul_pipe_t;

  mul_pipe_t mul_s0, mul_s1, mul_s2;

  // Stage 0: Booth encoding + partial product generation
  logic [127:0] partial_products [32];  /*verilator coverage_off*/ // cov-f2: pp_sum/pp_carry 與 booth_encode 為 dead code (從未賦值/呼叫, 無任何激勵可觸發); 僅加覆蓋註解, 未改任何邏輯 // 32 partial products for radix-4 Booth
  logic [127:0] pp_sum_s0, pp_carry_s0;

  // Radix-4 Booth encoding
  function automatic logic [2:0] booth_encode(input logic [2:0] bits);
    case (bits)
      3'b000: return 3'b000;  // 0
      3'b001: return 3'b001;  // +1
      3'b010: return 3'b001;  // +1
      3'b011: return 3'b010;  // +2
      3'b100: return 3'b110;  // -2
      3'b101: return 3'b101;  // -1
      3'b110: return 3'b101;  // -1
      3'b111: return 3'b000;  // 0
    endcase
  endfunction  /*verilator coverage_on*/

  // Stage 0: Input register + Booth encoding
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_s0 <= '0;
    end else begin
      if (uop_valid && uop_ready && is_mul) begin
        mul_s0.valid <= 1'b1;
        mul_s0.op_a <= is_signed_op ? $signed(operand_a) : operand_a;
        mul_s0.op_b <= (funct3 == 3'b010) ? operand_b :  // MULHSU: B unsigned
                       (is_signed_op ? $signed(operand_b) : operand_b);
        mul_s0.is_high <= is_high_result;
        mul_s0.is_signed_a <= is_signed_op;
        mul_s0.is_signed_b <= (funct3 != 3'b010) && is_signed_op;
        // v6.3.3 robfix: rob_idx 應回傳真實 ROB entry (原誤接 uop_id, 同 lsu_ld 修正)
        mul_s0.rob_idx <= uop.rob_idx;
        mul_s0.funct3 <= funct3;
      end else begin
        mul_s0.valid <= 1'b0;
      end
    end
  end

  // Wallace tree reduction (simplified: use built-in multiply)
  logic [127:0] mul_full_result;
  assign mul_full_result = $signed(mul_s0.op_a) * $signed(mul_s0.op_b);

  // Stage 1: Carry-save adder tree reduction
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_s1 <= '0;
    end else begin
      mul_s1 <= mul_s0;
    end
  end

  // Stage 2: Final addition + result selection
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_s2 <= '0;
    end else begin
      mul_s2 <= mul_s1;
    end
  end

  logic [63:0] mul_result;
  always_comb begin
    if (mul_s2.is_high) begin
      mul_result = mul_full_result[127:64];
    end else begin
      mul_result = mul_full_result[63:0];
    end
  end

  // ---------------------------------------------------------------------------
  // Divider (Restoring Division, 18-30 cycles, non-pipelined)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    DIV_IDLE,
    DIV_RUNNING,
    DIV_DONE
  } div_state_t;

  div_state_t div_state;
  logic [5:0] div_counter;        // 64 iterations max
  logic [127:0] div_remainder;    /*verilator coverage_off*/ // Extended remainder; cov-f2: div_quotient 為 dead 宣告 (僅 reset 寫 0, 從未被讀取/賦新值), toggle point 不可觸發; 僅加覆蓋註解, 未改任何邏輯
  logic [63:0]  div_quotient;  /*verilator coverage_on*/
  logic [63:0]  div_divisor;
  logic         div_sign_result;
  logic         div_is_rem;
  rob_idx_t     div_rob_idx;      // v6.3.3 robfix: rob_idx 隨 divider 走 (非管線化)

  // Signed division helpers
  logic [63:0] abs_a, abs_b;
  assign abs_a = (operand_a[63] && is_signed_op) ? -operand_a : operand_a;
  assign abs_b = (operand_b[63] && is_signed_op) ? -operand_b : operand_b;

  // Division state machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_state <= DIV_IDLE;
      div_counter <= '0;
      div_remainder <= '0;
      div_quotient <= '0;
      div_divisor <= '0;
      div_sign_result <= 1'b0;
      div_is_rem <= 1'b0;
      div_rob_idx <= '0;
    end else begin
      case (div_state)
        DIV_IDLE: begin
          if (uop_valid && uop_ready && (is_div || is_rem)) begin
            div_state <= DIV_RUNNING;
            div_counter <= 6'd0;
            div_remainder <= {64'b0, abs_a};
            div_divisor <= abs_b;
            div_sign_result <= (operand_a[63] ^ operand_b[63]) && is_signed_op;
            div_is_rem <= is_rem;
            div_rob_idx <= uop.rob_idx;
          end
        end
        DIV_RUNNING: begin
          // One iteration per cycle
          logic [127:0] rem_shifted;
          rem_shifted = div_remainder << 1;

          if (rem_shifted[127:64] >= div_divisor) begin
            div_remainder <= {rem_shifted[127:64] - div_divisor, rem_shifted[63:1], 1'b1};
          end else begin
            div_remainder <= rem_shifted;
          end

          div_counter <= div_counter + 1;

          if (div_counter >= 6'd63) begin
            div_state <= DIV_DONE;
          end
        end
        DIV_DONE: begin
          div_state <= DIV_IDLE;
        end
      endcase
    end
  end

  // Division result
  logic [63:0] div_result;
  always_comb begin
    if (div_is_rem) begin
      // Remainder: sign matches dividend
      if (operand_a[63] && is_signed_op)
        div_result = -div_remainder[127:64];
      else
        div_result = div_remainder[127:64];
    end else begin
      // Quotient
      if (div_sign_result)
        div_result = -div_remainder[63:0];
      else
        div_result = div_remainder[63:0];
    end
  end

  // Division by zero detection
  logic div_by_zero;
  assign div_by_zero = (operand_b == 64'b0) && (is_div || is_rem);

  // ---------------------------------------------------------------------------
  // Output Mux
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result <= '0;
      result_valid <= 1'b0;
      rob_idx <= '0;
      exception <= 1'b0;
      exc_code <= `EXC_NONE;
    end else begin
      // MUL result (3 cycles)
      if (mul_s2.valid) begin
        result <= mul_result;
        result_valid <= 1'b1;
        rob_idx <= mul_s2.rob_idx;
        exception <= 1'b0;
        exc_code <= `EXC_NONE;
      end
      // DIV/REM result (variable latency)
      else if (div_state == DIV_DONE) begin
        // v6.3.3 robfix: 兩條路徑都回傳 divider 捕捉的真實 rob_idx
        rob_idx <= div_rob_idx;
        if (div_by_zero) begin
          result <= '0;
          result_valid <= 1'b1;
          exception <= 1'b1;
          exc_code <= EXC_ILLEGAL_INST;  // Or dedicated div-by-zero exception
        end else begin
          result <= div_result;
          result_valid <= 1'b1;
          exception <= 1'b0;
          exc_code <= `EXC_NONE;
        end
      end else begin
        result_valid <= 1'b0;
      end
    end
  end

  assign uop_ready = (div_state == DIV_IDLE);  // Only accept when divider idle

  // ---------------------------------------------------------------------------
  // Performance Counters
  // ---------------------------------------------------------------------------
  logic [63:0] mul_count;
  logic [63:0] div_count;
  logic [63:0] div_stall_cycles;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_count <= '0;
      div_count <= '0;
      div_stall_cycles <= '0;
    end else begin
      if (mul_s2.valid) mul_count <= mul_count + 1;
      if (div_state == DIV_DONE) div_count <= div_count + 1;
      if (div_state == DIV_RUNNING) div_stall_cycles <= div_stall_cycles + 1;
    end
  end

endmodule : exu_mul
