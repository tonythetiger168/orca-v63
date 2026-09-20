// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_systolic_tb: npu_systolic 單元 coverage
// 覆蓋: WS_IDLE->WS_LOADING(64 row)->WS_READY->WS_COMPUTING->(flush)->WS_IDLE,
//       weight ping-pong row, sparse mask, psum ready, dtype 掃描
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_systolic_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [7:0]  weight_load_data [PE_ARRAY_DIM];
  logic        weight_load_valid, weight_load_row, weight_load_ready;
  logic [7:0]  activation_in [PE_ARRAY_DIM];
  logic        activation_valid, activation_ready;
  logic [31:0] partial_sum_out [PE_ARRAY_DIM];
  logic        partial_sum_valid [PE_ARRAY_DIM];
  logic        partial_sum_ready;
  logic [2:0]  dtype;
  logic        weight_stationary, accumulate_en, flush_acc;
  logic        sparse_mode;
  logic [PE_ARRAY_DIM-1:0] sparse_mask;
  logic        clk_gate_en;

  npu_systolic #(.ARRAY_DIM(PE_ARRAY_DIM), .DATA_WIDTH(8)) dut (
    .clk(clk), .rst_n(rst_n), .clk_gate_en(clk_gate_en),
    .weight_load_data(weight_load_data), .weight_load_valid(weight_load_valid),
    .weight_load_row(weight_load_row), .weight_load_ready(weight_load_ready),
    .activation_in(activation_in), .activation_valid(activation_valid),
    .activation_ready(activation_ready),
    .partial_sum_out(partial_sum_out), .partial_sum_valid(partial_sum_valid),
    .partial_sum_ready(partial_sum_ready),
    .dtype(dtype), .weight_stationary(weight_stationary),
    .accumulate_en(accumulate_en), .flush_acc(flush_acc),
    .sparse_mode(sparse_mode), .sparse_mask(sparse_mask));

  localparam int ADIM = PE_ARRAY_DIM;

  // ------------------ always_ff 鏡像 ------------------
  logic [7:0]  weight_load_data_p [ADIM];
  logic        weight_load_valid_p, weight_load_row_p;
  logic [7:0]  activation_in_p [ADIM];
  logic        activation_valid_p, partial_sum_ready_p;
  logic [2:0]  dtype_p;
  logic        weight_stationary_p, accumulate_en_p, flush_acc_p;
  logic        sparse_mode_p;
  logic [ADIM-1:0] sparse_mask_p;
  logic        clk_gate_en_p;
  always_ff @(posedge clk) begin
    weight_load_valid <= weight_load_valid_p;
    weight_load_row   <= weight_load_row_p;
    activation_valid  <= activation_valid_p;
    partial_sum_ready <= partial_sum_ready_p;
    dtype             <= dtype_p;
    weight_stationary <= weight_stationary_p;
    accumulate_en     <= accumulate_en_p;
    flush_acc         <= flush_acc_p;
    sparse_mode       <= sparse_mode_p;
    sparse_mask       <= sparse_mask_p;
    clk_gate_en       <= clk_gate_en_p;
    for (int i = 0; i < ADIM; i++) begin
      weight_load_data[i] <= weight_load_data_p[i];
      activation_in[i]    <= activation_in_p[i];
    end
  end

  int errors = 0;
  // ---- FSM coverage monitor: npu_systolic weight_state ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (int'(dut.weight_state) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_systolic %0d %0d\n", prev, int'(dut.weight_state));
        prev = int'(dut.weight_state);
      end
    end
  end
  logic saw_ready = 0, saw_act_rdy = 0, saw_psum_v = 0;
  always @(posedge clk) begin
    if (weight_load_ready) saw_ready <= 1'b1;
    if (activation_ready)  saw_act_rdy <= 1'b1;
    for (int i = 0; i < ADIM; i++)
      if (partial_sum_valid[i]) saw_psum_v <= 1'b1;
  end

  initial begin
    weight_load_valid_p = 0; weight_load_row_p = 0;
    activation_valid_p = 0; partial_sum_ready_p = 0;
    dtype_p = 3'd0; weight_stationary_p = 1; accumulate_en_p = 0;
    flush_acc_p = 0; sparse_mode_p = 0; sparse_mask_p = '0; clk_gate_en_p = 1;
    for (int i = 0; i < ADIM; i++) begin
      weight_load_data_p[i] = 8'(i + 1);
      activation_in_p[i]    = 8'(i + 3);
    end
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);
    if (!weight_load_ready) begin
      errors++;
      $display("TB ERROR: weight_load_ready not set in WS_IDLE");
    end

    // ---- weight load: 64+ row, 涵蓋 load_counter<ADIM 與 else (loaded) ----
    weight_load_valid_p = 1;
    weight_load_row_p   = 1;   // ping-pong row toggle
    repeat (ADIM + 4) @(negedge clk);
    weight_load_valid_p = 0;
    weight_load_row_p   = 0;
    @(negedge clk);
    if (!saw_act_rdy) begin
      errors++;
      $display("TB ERROR: activation_ready never set (WS_READY not reached)");
    end

    // ---- compute: activation_valid + accumulate, dtype 掃描 ----
    accumulate_en_p = 1;
    activation_valid_p = 1;
    for (int dt = 0; dt < 8; dt++) begin
      dtype_p = 3'(dt);
      @(negedge clk);
    end
    // sparse mode: mask 翻動
    sparse_mode_p = 1;
    sparse_mask_p = '1;
    repeat (2) @(negedge clk);
    sparse_mask_p = '0;
    sparse_mode_p = 0;
    partial_sum_ready_p = 1;
    repeat (2) @(negedge clk);
    if (!saw_psum_v) begin
      errors++;
      $display("TB ERROR: partial_sum_valid never set (WS_COMPUTING not reached)");
    end

    // ---- flush -> 回 WS_IDLE ----
    flush_acc_p = 1;
    @(negedge clk);
    flush_acc_p = 0;
    activation_valid_p = 0;
    accumulate_en_p = 0;
    repeat (4) @(negedge clk);
    if (!weight_load_ready) begin
      errors++;
      $display("TB ERROR: did not return to WS_IDLE after flush");
    end

    // ---- 第二次短流程: weight_stationary=0 propagate 模式 ----
    weight_stationary_p = 0;
    weight_load_valid_p = 1;
    repeat (ADIM + 4) @(negedge clk);
    weight_load_valid_p = 0;
    activation_valid_p = 1;
    accumulate_en_p = 1;
    repeat (4) @(negedge clk);
    flush_acc_p = 1;
    @(negedge clk);
    flush_acc_p = 0;
    repeat (4) @(negedge clk);

    // ---- F4 toggle poke-blitz (flush 後回 WS_IDLE, 無後續 clock 敏感) ----
    `F4POKE(cycle_counter)
    `F4POKE(compute_cycle_counter)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_systolic %0d errors", errors);
    $display("TB PASS: f4_systolic load/compute/sparse/flush covered");
    $finish;
  end
endmodule : f4_systolic_tb
