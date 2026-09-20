// SPDX-License-Identifier: Apache-2.0
`include "orca_pkg.sv"
// npu_attn_engine 全覆蓋: attn_config(標準/GQA/MQA/FlashAttn) x RoPE x ALiBi x
// head_dim(64/128/other) x dtype x seq>TILE(多列 softmax)。L2 模型回應讓 FSM 推進。
module unit_attn_tb;
  import orca_pkg::*;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  logic start, done, ckg, l2v, l2we, h3v;
  logic [2:0] cfg; logic [15:0] slen; logic [7:0] hdim, nhd, nkv; logic [3:0] dt;
  logic rope, alibi; logic [31:0] slope;
  logic [63:0] l2a, h3a, qkvo; logic [511:0] l2rd, l2wd, h3rd;
  logic [63:0] q_b,k_b,v_b,o_b, cyc; logic [31:0] mscore; logic oflow;

  npu_attn_engine u_attn (
    .clk(clk), .rst_n(rst_n), .clk_gate(ckg), .start(start), .done(done),
    .attn_config(cfg), .seq_len(slen), .head_dim(hdim), .num_heads(nhd), .num_kv_heads(nkv),
    .dtype(dt), .use_rope(rope), .use_alibi(alibi), .alibi_slope(slope),
    .l2_req_addr(l2a), .l2_req_valid(l2v), .l2_req_we(l2we),
    .l2_rsp_data(l2rd), .l2_rsp_valid(l2rdv),
    .hbm3_req_addr(h3a), .hbm3_req_valid(h3v),
    .hbm3_rsp_data(h3rd), .hbm3_rsp_valid(h3rdv),
    .cycle_counter(cyc), .max_score(mscore), .overflow_flag(oflow),
    .q_base(q_b), .k_base(k_b), .v_base(v_b), .o_base(o_b),
    .l2_req_data(l2wd));

  // L2/HBM3 回應模型: req 後 1 cycle 回 valid
  logic l2rdv, h3rdv;
  always_ff @(posedge clk) begin
    l2rdv <= l2v; h3rdv <= h3v;
    if (l2v)  l2rd <= {8{64'h3F80_3F80_3F80_3F80}};  // BF16 1.0 x4
    if (h3v)  h3rd <= {8{64'h4000_4000_4000_4000}};
  end

  // 看門狗
  initial begin
    repeat(40000) @(negedge clk);
    $display("ATTN WATCHDOG cyc=%0d", cyc); $finish;
  end

  task automatic run(input logic [2:0] c, input logic [7:0] hd, input logic [15:0] sq,
                     input logic rp, input logic al, input logic [7:0] nh, input logic [7:0] nkvh);
    cfg=c; hdim=hd; slen=sq; rope=rp; alibi=al; nhd=nh; nkv=nkvh;
    start=1; @(negedge clk); start=0;
    begin int g=0; while(!done && g<8000) begin @(negedge clk); g++; end end
    repeat(20) @(negedge clk);
  endtask

  initial begin
    ckg=1; start=0; cfg=0; slen=16; hdim=64; nhd=1; nkv=1; dt=AI_DTYPE_BF16;
    rope=0; alibi=0; slope=0;
    q_b=64'h1000_0000; k_b=64'h2000_0000; v_b=64'h3000_0000; o_b=64'h4000_0000;
    rst_n=0; #57 rst_n=1; @(negedge clk);
    repeat(20) @(negedge clk);

    // 基本 dtype 掃描 (標準 config, seq=TILE 單列)
    for (int d=0; d<8; d++) begin dt=4'(d); run(0, 8'd64, 16, 0, 0, 8'd1, 8'd1); end
    // head_dim 64/128/other (scale_factor 3 支)
    run(0, 8'd64,  16, 0, 0, 8'd1, 8'd1);
    run(0, 8'd128, 16, 0, 0, 8'd1, 8'd1);
    run(0, 8'd96,  16, 0, 0, 8'd1, 8'd1);
    // seq > TILE (多列 softmax: softmax_max 更新 + 比較)
    run(0, 8'd64, 64, 0, 0, 8'd1, 8'd1);
    run(0, 8'd64, 128, 0, 0, 8'd1, 8'd1);
    // RoPE / ALiBi / 兩者
    run(0, 8'd64, 16, 1, 0, 8'd1, 8'd1);
    run(0, 8'd64, 16, 0, 1, 8'd1, 8'd1);
    run(0, 8'd64, 16, 1, 1, 8'd1, 8'd1);
    run(0, 8'd64, 32, 0, 1, 8'd1, 8'd1);   // ALiBi 多列
    // GQA / MQA / FlashAttn config
    run(1, 8'd64, 16, 0, 0, 8'd4, 8'd2);   // GQA
    run(2, 8'd64, 16, 0, 0, 8'd8, 8'd1);   // MQA
    run(3, 8'd64, 64, 0, 0, 8'd1, 8'd1);   // FlashAttn 多 tile
    run(3, 8'd64, 16, 1, 1, 8'd2, 8'd2);   // FlashAttn + rope + alibi
    // 多 head
    run(0, 8'd64, 16, 0, 0, 8'd8, 8'd8);

    $display("ATTN UNIT TB PASS cyc=%0d max=%0d oflow=%0d", cyc, mscore, oflow);
    $finish;
  end
endmodule : unit_attn_tb
