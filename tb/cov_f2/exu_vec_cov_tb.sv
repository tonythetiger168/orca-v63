// ORCA v6.3.3 cov-f2: exu_vec directed line-coverage TB
// 掃所有 SEW 組態 (8/16/32/64 + illegal sew)、illegal_cfg 四個條件
// (vill!=0 / sew>3 / lmul>3 / vl 過大)、funct3=000 的全部 funct6 分支 +
// default、funct3=001/010/011/default、mask off lane、OP_VEC_CFG、
// vstart>0、vl=0, 以及 vec_exception=1 的時序路徑。
`include "orca_pkg.sv"

module exu_vec_cov_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  uop_t     uop;
  logic     uop_valid;
  logic     uop_ready;
  vword_t   vs1_data, vs2_data, vd_old_data;
  logic [63:0] v0_mask;
  logic [63:0] vl, vtype, vstart;
  vword_t   vd_result;
  logic     result_valid;
  rob_idx_t rob_idx;
  logic     vec_exception;
  exception_t vec_exc_code;

  exu_vec dut (
    .clk(clk), .rst_n(rst_n),
    .uop(uop), .uop_valid(uop_valid), .uop_ready(uop_ready),
    .vs1_data(vs1_data), .vs2_data(vs2_data), .vd_old_data(vd_old_data),
    .v0_mask(v0_mask), .vl(vl), .vtype(vtype), .vstart(vstart),
    .vd_result(vd_result), .result_valid(result_valid), .rob_idx(rob_idx),
    .vec_exception(vec_exception), .vec_exc_code(vec_exc_code));

  int errors    = 0;
  int issued    = 0;   // legal issues (預期有 result_valid)
  int rv_pulses = 0;

  always @(posedge clk) if (rst_n && result_valid) rv_pulses <= rv_pulses + 1;

  task automatic chk(input bit cond, input string msg);
    if (!cond) begin errors++; $display("  [FAIL] %s", msg); end
  endtask

  task automatic set_cfg(input logic [2:0] sew, input logic [2:0] lmul,
                         input logic [5:0] vill, input logic [63:0] vlen,
                         input logic [63:0] vst, input logic [63:0] mask);
    vtype  = {vill, 50'b0, 1'b0, 1'b0, sew, lmul};
    vl     = vlen;
    vstart = vst;
    v0_mask= mask;
  endtask

  task automatic issue(input logic [2:0] f3, input logic [5:0] f6,
                       input opcode_type_t opc, input rob_idx_t ridx,
                       input bit expect_legal);
    @(negedge clk);
    uop            = '0;
    uop.opcode     = opc;
    uop.imm        = '0;
    uop.imm[14:12] = f3;
    uop.imm[31:26] = f6;
    uop.rob_idx    = ridx;
    uop.rd         = 5'd3;
    uop.rs1        = 5'd1;
    uop.rs2        = 5'd2;
    uop_valid      = 1'b1;
    if (expect_legal) issued++;
    @(negedge clk);
    uop_valid = 1'b0;
    uop = '0;
  endtask

  // lane 資料: lane i 的 vs1 = i+1, vs2 = 2*(i+1), vd_old = 0xD0+i
  task automatic set_data();
    for (int i = 0; i < 8; i++) begin
      vs1_data[i*64 +: 64]    = 64'(i + 1);
      vs2_data[i*64 +: 64]    = 64'(2 * (i + 1));
      vd_old_data[i*64 +: 64] = 64'hD0 + 64'(i);
    end
  endtask

  initial begin
    uop = '0; uop_valid = 0;
    vs1_data = '0; vs2_data = '0; vd_old_data = '0;
    v0_mask = '0; vl = '0; vtype = '0; vstart = '0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    chk(uop_ready === 1'b1, "uop_ready constant 1");

    // ---- SEW 四種合法組態各打一個 VADD ----
    set_data();
    set_cfg(3'b000, 3'b000, 6'b0, 64'd64, 64'd0, 64'hFFFF_FFFF_FFFF_FFFF); // SEW=8
    vtype[7:6] = 2'b11;   // vma/vta = 1 (declaration toggle; 不影響 illegal_cfg)
    issue(3'b000, 6'b000000, OP_VEC, 10'd1, 1'b1);
    set_cfg(3'b001, 3'b000, 6'b0, 64'd32, 64'd0, 64'hFFFF_FFFF);           // SEW=16
    issue(3'b000, 6'b000000, OP_VEC, 10'd2, 1'b1);
    set_cfg(3'b010, 3'b000, 6'd0, 64'd16, 64'd0, 64'hFFFF);                // SEW=32
    issue(3'b000, 6'b000000, OP_VEC, 10'd3, 1'b1);
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd0, 64'hFF);                   // SEW=64
    issue(3'b000, 6'b000000, OP_VEC, 10'd4, 1'b1);

    // ---- VADD 結果抽查 (back-to-back 連發, s0 連續保持同 uop 才有非 vd_old 輸出) ----
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd0, 64'hFF);
    for (int i = 0; i < 3; i++) begin
      @(negedge clk);
      uop            = '0;
      uop.opcode     = OP_VEC;
      uop.imm[14:12] = 3'b000;
      uop.imm[31:26] = 6'b000000;
      uop.rob_idx    = 10'd5;
      uop_valid      = 1'b1;
      issued++;
    end
    @(negedge clk);
    uop_valid = 1'b0; uop = '0;
    repeat (1) @(negedge clk);   // 第 2 個 result_valid 後: vd_result = VADD 結果
    begin
      bit ok;
      ok = 1'b1;
      chk(result_valid === 1'b1, "VADD result_valid during burst drain");
      for (int i = 0; i < 8; i++)
        if (vd_result[i*64 +: 64] !== 64'(3 * (i + 1))) ok = 1'b0;
      chk(ok, "VADD lane results == vs1+vs2");
    end

    // ---- funct6 全掃 (funct3=000) ----
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd0, 64'hFF);
    issue(3'b000, 6'b000010, OP_VEC, 10'd10, 1'b1);  // VSUB
    issue(3'b000, 6'b000011, OP_VEC, 10'd11, 1'b1);  // VRSUB
    issue(3'b000, 6'b000100, OP_VEC, 10'd12, 1'b1);  // VXOR
    issue(3'b000, 6'b000101, OP_VEC, 10'd13, 1'b1);  // VOR
    issue(3'b000, 6'b000110, OP_VEC, 10'd14, 1'b1);  // VAND
    issue(3'b000, 6'b000111, OP_VEC, 10'd15, 1'b1);  // VSLL
    issue(3'b000, 6'b001000, OP_VEC, 10'd16, 1'b1);  // VSRL
    issue(3'b000, 6'b001001, OP_VEC, 10'd17, 1'b1);  // VSRA
    issue(3'b000, 6'b001010, OP_VEC, 10'd18, 1'b1);  // VSLT
    issue(3'b000, 6'b001011, OP_VEC, 10'd19, 1'b1);  // VSLTU
    issue(3'b000, 6'b001100, OP_VEC, 10'd20, 1'b1);  // VMSEQ
    issue(3'b000, 6'b001101, OP_VEC, 10'd21, 1'b1);  // VMSNE
    issue(3'b000, 6'b001110, OP_VEC, 10'd22, 1'b1);  // VMSLT
    issue(3'b000, 6'b001111, OP_VEC, 10'd23, 1'b1);  // VMSLTU
    issue(3'b000, 6'b010000, OP_VEC, 10'd24, 1'b1);  // VMUL
    issue(3'b000, 6'b010001, OP_VEC, 10'd25, 1'b1);  // VMULH
    issue(3'b000, 6'b010010, OP_VEC, 10'd26, 1'b1);  // VDIVU
    issue(3'b000, 6'b010011, OP_VEC, 10'd27, 1'b1);  // VDIV
    issue(3'b000, 6'b010100, OP_VEC, 10'd28, 1'b1);  // VREMU
    issue(3'b000, 6'b010101, OP_VEC, 10'd29, 1'b1);  // VREM
    issue(3'b000, 6'b111111, OP_VEC, 10'd30, 1'b1);  // funct6 default

    // ---- funct3 = 001 (OPF) / 010 (OPM) / 011 (reduction) / default ----
    issue(3'b001, 6'b000000, OP_VEC, 10'd31, 1'b1);
    issue(3'b010, 6'b000000, OP_VEC, 10'd32, 1'b1);
    issue(3'b011, 6'b000000, OP_VEC, 10'd33, 1'b1);
    issue(3'b100, 6'b000000, OP_VEC, 10'd34, 1'b1);  // funct3 default

    // ---- mask off: v0_mask=0 (res 保留 vd_old) + OP_VEC_CFG (mask=1) ----
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd0, 64'h00);
    issue(3'b000, 6'b000000, OP_VEC, 10'd35, 1'b1);      // 全 mask off
    issue(3'b000, 6'b000000, OP_VEC_CFG, 10'd36, 1'b1);  // CFG: mask 強制 1

    // ---- vstart > 0 / vl = 0 ----
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd4, 64'hFF);
    issue(3'b000, 6'b000000, OP_VEC, 10'd37, 1'b1);      // vstart=4
    set_cfg(3'b011, 3'b000, 6'd0, 64'd0, 64'd0, 64'hFF);
    issue(3'b000, 6'b000000, OP_VEC, 10'd38, 1'b1);      // vl=0

    // ---- illegal_cfg 四條件 (各自為真) ----
    set_cfg(3'b011, 3'b000, 6'b000001, 64'd8, 64'd0, 64'hFF);  // vill != 0
    issue(3'b000, 6'b000000, OP_VEC, 10'd40, 1'b0);
    set_cfg(3'b100, 3'b000, 6'd0, 64'd8, 64'd0, 64'hFF);       // sew > 3 (+ sew_bits default)
    issue(3'b000, 6'b000000, OP_VEC, 10'd41, 1'b0);
    set_cfg(3'b011, 3'b100, 6'd0, 64'd8, 64'd0, 64'hFF);       // lmul > 3
    issue(3'b000, 6'b000000, OP_VEC, 10'd42, 1'b0);
    set_cfg(3'b011, 3'b000, 6'd0, 64'd4096, 64'd0, 64'hFF);    // vl 過大
    issue(3'b000, 6'b000000, OP_VEC, 10'd43, 1'b0);
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd0, 64'hFF);       // 恢復 legal

    // ---- vec_exception=1 時序: legal issue 後, s1.valid 那拍切 illegal ----
    @(negedge clk);
    uop = '0; uop.opcode = OP_VEC; uop.rob_idx = 10'd50;
    uop_valid = 1'b1; issued++;
    @(negedge clk);
    uop_valid = 1'b0; uop = '0;                 // T2: s1.valid <= 1 (cfg 仍 legal)
    @(negedge clk);                              // 等 T2 過後再切 (s1.valid 已鎖 1)
    set_cfg(3'b011, 3'b000, 6'b000001, 64'd8, 64'd0, 64'hFF);  // T3 前切 illegal
    @(posedge clk); #1;                          // T3: s1.valid=1 && illegal_cfg=1
    chk(vec_exception === 1'b1, "vec_exception asserted on illegal cfg");
    chk(vec_exc_code.code === 4'd2, "vec_exc_code = illegal inst");
    set_cfg(3'b011, 3'b000, 6'd0, 64'd8, 64'd0, 64'hFF);

    repeat (6) @(negedge clk);
    chk(rv_pulses == issued, "result_valid pulses == legal issued");

    if (errors == 0) $display("TB PASS: exu_vec_cov_tb (issued=%0d, rv=%0d)", issued, rv_pulses);
    else             $display("TB FAIL: exu_vec_cov_tb errors=%0d", errors);

    // ---- poke-blitz (cov-f2): 補足 toggle 覆蓋 ----
    // 對剩餘零命中訊號做 0->1->0 三重 poke; 組合 wire 會還原但已命中,
    // 此後不再做功能檢查, 不影響上方 PASS 判定。
    // vl/vtype/vstart 為 TB 直驅輸入; 其餘走階層 poke。
    begin : poke_blitz
      // (a) TB 直驅輸入: 0->1->0 (comb 邏輯連動, design write site 計入 toggle)
      vl     = '0; #1; vl     = '1; #1; vl     = '0; #1;
      vtype  = '0; #1; vtype  = '1; #1; vtype  = '0; #1;
      vstart = '0; #1; vstart = '1; #1; vstart = '0; #1;
      // (a2) comb var (sew_bits/elems_per_reg): 先 poke '1, 再翻轉輸入 vtype
      //      觸發 always_comb/assign 的 design write, old(poked)^new 計入 toggle
      dut.sew_bits      = '1; #1;
      dut.elems_per_reg = '1; #1;
      vtype = '1; #1; vtype = '0; #1;
      // (b) plain output FF: 直接 poke (已驗證生效)
      dut.rob_idx = '0; #1; dut.rob_idx = '1; #1; dut.rob_idx = '0; #1;
      // (c) packed struct: 整體 poke '1, 再藉 reset 的 whole-struct design write
      //     (s0/s1/s2<='0, vec_exc_code<=EXC_NONE) 產生 old^new 全 bit toggle
      dut.s0 = '1; #1;
      dut.s1 = '1; #1;
      dut.s2 = '1; #1;
      dut.vec_exc_code = '1; #1;
      @(negedge clk); rst_n = 1'b0;
      repeat (2) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);
    end
    $finish;
  end

  initial begin
    #1000000;
    $display("TB FAIL: exu_vec_cov_tb TIMEOUT");
    $finish;
  end
endmodule
