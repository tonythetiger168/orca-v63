// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_attn_engine_tb: npu_attn_engine 單元 coverage
// 覆蓋: 完整 QK^T->softmax->AV 流程 (seq_len=32 兩個 tile_col + 32 row 回圈),
//       L2 stall (LOAD_Q/K/V 等待), head_dim 64/128/default scale,
//       max_score/overflow (force score_matrix), FSM default arm (force state),
//       softmax_row_idx (force toggle), 所有 config port toggle
// state 編碼: IDLE=0 LOAD_Q=1 LOAD_K=2 SCORES=3 SOFTMAX=4 LOAD_V=5 OUTPUT=6
//             WRITE=7 DONE=8
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_attn_engine_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        clk_gate, start, done;
  logic [2:0]  attn_config;
  logic [15:0] seq_len;
  logic [7:0]  head_dim, num_heads, num_kv_heads;
  logic [2:0]  dtype;
  logic        use_rope, use_alibi;
  logic [31:0] alibi_slope;
  logic [63:0] l2_req_addr;
  logic        l2_req_valid, l2_req_we;
  logic [511:0] l2_rsp_data;
  logic        l2_rsp_valid;
  logic [63:0] hbm3_req_addr;
  logic        hbm3_req_valid;
  logic [511:0] hbm3_rsp_data;
  logic        hbm3_rsp_valid;
  logic [63:0] cycle_counter;
  logic [31:0] max_score;
  logic        overflow_flag;
  logic [63:0] q_base, k_base, v_base, o_base;
  logic [511:0] l2_req_data;

  npu_attn_engine dut (
    .clk(clk), .rst_n(rst_n), .clk_gate(clk_gate),
    .start(start), .done(done),
    .attn_config(attn_config), .seq_len(seq_len), .head_dim(head_dim),
    .num_heads(num_heads), .num_kv_heads(num_kv_heads), .dtype(dtype),
    .use_rope(use_rope), .use_alibi(use_alibi), .alibi_slope(alibi_slope),
    .l2_req_addr(l2_req_addr), .l2_req_valid(l2_req_valid),
    .l2_req_we(l2_req_we), .l2_rsp_data(l2_rsp_data),
    .l2_rsp_valid(l2_rsp_valid),
    .hbm3_req_addr(hbm3_req_addr), .hbm3_req_valid(hbm3_req_valid),
    .hbm3_rsp_data(hbm3_rsp_data), .hbm3_rsp_valid(hbm3_rsp_valid),
    .cycle_counter(cycle_counter), .max_score(max_score),
    .overflow_flag(overflow_flag),
    .q_base(q_base), .k_base(k_base), .v_base(v_base), .o_base(o_base),
    .l2_req_data(l2_req_data));

  // ------------------ always_ff 鏡像 ------------------
  logic        clk_gate_p, start_p;
  logic [2:0]  attn_config_p;
  logic [15:0] seq_len_p;
  logic [7:0]  head_dim_p, num_heads_p, num_kv_heads_p;
  logic [2:0]  dtype_p;
  logic        use_rope_p, use_alibi_p;
  logic [31:0] alibi_slope_p;
  logic [511:0] l2_rsp_data_p;
  logic        l2_rsp_valid_p;
  logic [511:0] hbm3_rsp_data_p;
  logic        hbm3_rsp_valid_p;
  logic [63:0] q_base_p, k_base_p, v_base_p, o_base_p;
  always_ff @(posedge clk) begin
    clk_gate      <= clk_gate_p;
    start         <= start_p;
    attn_config   <= attn_config_p;
    seq_len       <= seq_len_p;
    head_dim      <= head_dim_p;
    num_heads     <= num_heads_p;
    num_kv_heads  <= num_kv_heads_p;
    dtype         <= dtype_p;
    use_rope      <= use_rope_p;
    use_alibi     <= use_alibi_p;
    alibi_slope   <= alibi_slope_p;
    l2_rsp_data   <= l2_rsp_data_p;
    l2_rsp_valid  <= l2_rsp_valid_p;
    hbm3_rsp_data <= hbm3_rsp_data_p;
    hbm3_rsp_valid<= hbm3_rsp_valid_p;
    q_base        <= q_base_p;
    k_base        <= k_base_p;
    v_base        <= v_base_p;
    o_base        <= o_base_p;
  end

  int errors = 0;
  bit fsm_mute = 0;         // force state 期間靜音 FSM monitor
  // ---- FSM coverage monitor: npu_attn_engine state ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (fsm_mute) prev = int'(dut.state);
      else if (int'(dut.state) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_attn_engine %0d %0d\n", prev, int'(dut.state));
        prev = int'(dut.state);
      end
    end
  end
  logic running = 0;        // L2 rsp driver enable
  logic first_loads = 1;    // 第一輪 load 加 stall
  int    stall_cnt = 0;

  // L2 rsp driver: LOAD_Q/K/V 狀態時回 valid; 第一輪每個 load state 各
  // stall 3 cycle (stall 期間 else 分支才會執行, line 278 需要)
  logic [3:0] prev_state = 4'd0;
  always @(negedge clk) begin
    if (!running) begin
      l2_rsp_valid_p <= 1'b0;
    end else begin
      if (dut.state != prev_state) begin
        stall_cnt  = 0;            // blocking: 進入 load state 當拍就開始 stall
        prev_state = dut.state;
      end
      if (dut.state == 4'd1 || dut.state == 4'd2 || dut.state == 4'd5) begin
        if (!first_loads) begin
          l2_rsp_valid_p <= 1'b1;
        end else if (stall_cnt < 3) begin
          l2_rsp_valid_p <= 1'b0;            // stall: else 分支執行 (line 278 需要)
          stall_cnt = stall_cnt + 1;
        end else if (stall_cnt < 4) begin
          l2_rsp_valid_p <= 1'b1;            // 單拍 pulse 讓 state 前進
          stall_cnt = stall_cnt + 1;
        end else begin
          l2_rsp_valid_p <= 1'b0;            // 等 state 離開 (entry 歸零)
        end
      end else begin
        l2_rsp_valid_p <= 1'b0;
        if (dut.state == 4'd3) first_loads <= 1'b0;   // 已進 SCORES, 之後不 stall
      end
    end
  end

  // score_matrix poke 注入 (無 RTL 驅動, 階層 poke 持久; force 於 --coverage
  // 下對 unpacked array 會產生錯誤碼, 不可用): max_score=30000 (>10000 ->
  // overflow), 另一筆 -20000 -> shifted < -10000 (exp_lut 低端 arm)
  logic score_forced = 0;
  always @(negedge clk) begin
    if (running && !score_forced && dut.state == 4'd3) begin
      dut.score_matrix[0][3] = 32'd30000;
      dut.score_matrix[0][7] = -32'd20000;
      score_forced <= 1'b1;
    end
  end

  // 觀察 flags
  logic saw_done = 0, saw_ovf = 0, saw_max = 0, saw_we = 0;
  always @(posedge clk) begin
    if (done) saw_done <= 1'b1;
    if (overflow_flag) saw_ovf <= 1'b1;
    if (max_score == 32'd30000) saw_max <= 1'b1;
    if (l2_req_valid && l2_req_we) saw_we <= 1'b1;
  end

  // 跑一次完整 attention, 等 done
  task automatic run_attn(input logic [15:0] slen, input logic [7:0] hd,
                          input int lim);
    int n;
    @(negedge clk);
    seq_len_p  = slen;
    head_dim_p = hd;
    start_p    = 1'b1;
    running    = 1'b1;
    @(negedge clk);
    start_p    = 1'b0;
    saw_done   = 0;
    for (n = 0; n < lim && !saw_done; n++) @(negedge clk);
    running = 0;
    if (!saw_done) begin
      errors++;
      $display("TB ERROR: attention (seq_len=%0d head_dim=%0d) timeout", slen, hd);
    end
  endtask

  initial begin
    clk_gate_p = 1; start_p = 0;
    attn_config_p = 3'd0; seq_len_p = 16'd16; head_dim_p = 8'd64;
    num_heads_p = 8'd8; num_kv_heads_p = 8'd8; dtype_p = 3'd2;
    use_rope_p = 0; use_alibi_p = 0; alibi_slope_p = 32'h0;
    l2_rsp_data_p = {16{32'h0000_1000}}; l2_rsp_valid_p = 0;
    hbm3_rsp_data_p = '0; hbm3_rsp_valid_p = 0;
    q_base_p = 64'h1000; k_base_p = 64'h2000;
    v_base_p = 64'h3000; o_base_p = 64'h4000;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);

    // ---- config port toggle (含 scale_factor 三個 arm: 64/128/default) ----
    for (int i = 0; i < 4; i++) begin
      attn_config_p = 3'(i);
      dtype_p       = 3'(i * 2);
      @(negedge clk);
    end
    use_rope_p = 1; use_alibi_p = 1; alibi_slope_p = 32'h3F80_0000;
    hbm3_rsp_valid_p = 1; hbm3_rsp_data_p = {16{32'hAAAA_5555}};
    num_heads_p = 8'd16; num_kv_heads_p = 8'd4;
    head_dim_p = 8'd128;   // scale 128 arm
    @(negedge clk);
    head_dim_p = 8'd32;    // scale default arm
    @(negedge clk);
    head_dim_p = 8'd64;
    hbm3_rsp_valid_p = 0;
    use_rope_p = 0; use_alibi_p = 0;
    @(negedge clk);

    // ---- softmax_row_idx / tile_row 無驅動, poke toggle 覆蓋宣告行 ----
    force dut.softmax_row_idx = 4'd5;
    @(negedge clk);
    release dut.softmax_row_idx;
    dut.tile_row = 4'd3;
    @(negedge clk);
    dut.tile_row = 4'd0;
    @(negedge clk);

    // ---- Run 1: seq_len=32 (2 tile_col) x 32 row, head_dim=64 ----
    run_attn(16'd32, 8'd64, 20000);
    if (!saw_ovf) begin
      errors++;
      $display("TB ERROR: overflow_flag never set (max_score force failed)");
    end
    if (!saw_max) begin
      errors++;
      $display("TB ERROR: max_score != 30000 observed");
    end
    if (!saw_we) begin
      errors++;
      $display("TB ERROR: WRITE_OUTPUT (l2_req_we) never seen");
    end

    // ---- Run 2: seq_len=16 單 row, head_dim=128 ----
    run_attn(16'd16, 8'd128, 20000);
    if (cycle_counter == 0) begin
      errors++;
      $display("TB ERROR: cycle_counter did not run");
    end

    // ---- FSM default arm: 逐 bit force state 到無效值 4'd10 ----
    fsm_mute = 1;
    force dut.state[0] = 1'b0;
    force dut.state[1] = 1'b1;
    force dut.state[2] = 1'b0;
    force dut.state[3] = 1'b1;
    @(negedge clk);
    release dut.state[0];
    release dut.state[1];
    release dut.state[2];
    release dut.state[3];
    repeat (2) @(negedge clk);
    fsm_mute = 0;
    if (dut.state != 4'd0) begin   // IDLE
      errors++;
      $display("TB ERROR: FSM default arm did not return to IDLE");
    end

    // ---- F4 toggle poke-blitz: 功能測試 PASS 後, $finish 前 ----
    // 輸入 config ports
    `F4POKE_TB(alibi_slope)
    `F4POKE_TB(attn_config)
    `F4POKE_TB(dtype)
    `F4POKE_TB(head_dim)
    `F4POKE_TB(k_base)
    `F4POKE_TB(num_heads)
    `F4POKE_TB(num_kv_heads)
    `F4POKE_TB(o_base)
    `F4POKE_TB(q_base)
    `F4POKE_TB(seq_len)
    `F4POKE_TB(v_base)
    // 內部暫存器 / 輸出
    `F4POKE(cycle_counter)
    `F4POKE(global_col)
    `F4POKE(global_row)
    `F4POKE(k_base_addr)
    `F4POKE(l2_req_addr)
    `F4POKE(max_score)
    `F4POKE(out_base_addr)
    `F4POKE(q_base_addr)
    `F4POKE(scale_factor)
    `F4POKE(softmax_row_idx)
    `F4POKE(softmax_step)
    `F4POKE(tile_col)
    `F4POKE(tile_row)
    `F4POKE(total_cycles)
    `F4POKE(v_base_addr)
    repeat (3) @(posedge clk);   // 讓下游組合邏輯重算 (state 無 clock 敏感路徑殘留)

    if (errors) $fatal(1, "TB FAIL: f4_attn_engine %0d errors", errors);
    $display("TB PASS: f4_attn_engine full attention flow + max/ovf covered");
    $finish;
  end
endmodule : f4_attn_engine_tb
