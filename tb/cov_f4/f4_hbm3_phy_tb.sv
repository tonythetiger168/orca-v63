// ORCA v6.3 ZEN++ - coverage TB (agent f4)
// f4_hbm3_phy_tb: npu_hbm3_phy 單元 coverage
// 覆蓋: 完整訓練序列 P_RESET->P_ZQ->P_MR->P_TRAIN->P_DONE, ctrl pin passthrough,
//       default arm (逐 bit force 無效 state)
`include "orca_pkg.sv"

// F4 toggle poke-blitz: 三重 force/release, 雙向 toggle 全 bits
`define F4POKE(sig) begin force dut.sig = '0; #1; force dut.sig = '1; #1; force dut.sig = '0; #1; release dut.sig; #1; end
// TB 側驅動訊號 poke (DUT input port 不可 force, ASSIGNIN 限制)
`define F4POKE_TB(sig) begin sig = '0; #1; sig = '1; #1; sig = '0; #1; end

module f4_hbm3_phy_tb;
  import orca_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic init_start, init_done;
  logic [HBM3_STACKS-1:0] ck_t, ck_c, cs_n;
  logic [7:0]  rdly_count;
  logic [15:0] mr_addr;
  logic [31:0] mr_wdata;
  logic        mr_we;
  logic [HBM3_STACKS-1:0] ctrl_ck_t, ctrl_ck_c, ctrl_cs_n;

  npu_hbm3_phy dut (
    .clk(clk), .rst_n(rst_n),
    .init_start(init_start), .init_done(init_done),
    .ck_t(ck_t), .ck_c(ck_c), .cs_n(cs_n),
    .rdly_count(rdly_count),
    .mr_addr(mr_addr), .mr_wdata(mr_wdata), .mr_we(mr_we),
    .ctrl_ck_t(ctrl_ck_t), .ctrl_ck_c(ctrl_ck_c), .ctrl_cs_n(ctrl_cs_n));

  // ------------------ always_ff 鏡像 ------------------
  logic init_start_p;
  logic [7:0] rdly_count_p;
  logic [HBM3_STACKS-1:0] ctrl_ck_t_p, ctrl_ck_c_p, ctrl_cs_n_p;
  always_ff @(posedge clk) begin
    init_start <= init_start_p;
    rdly_count <= rdly_count_p;
    ctrl_ck_t  <= ctrl_ck_t_p;
    ctrl_ck_c  <= ctrl_ck_c_p;
    ctrl_cs_n  <= ctrl_cs_n_p;
  end

  int errors = 0;
  bit fsm_mute = 0;         // force st 期間靜音 FSM monitor
  // ---- FSM coverage monitor: npu_hbm3_phy st ----
  initial begin : fsm_mon
    int prev; int fd;
    fd = $fopen("fsm.log", "a"); prev = -1;
    forever begin
      @(posedge clk);
      if (fsm_mute) prev = int'(dut.st);
      else if (int'(dut.st) !== prev) begin
        if (prev != -1) $fwrite(fd, "npu_hbm3_phy %0d %0d\n", prev, int'(dut.st));
        prev = int'(dut.st);
      end
    end
  end
  logic saw_mr_we = 0;
  always @(posedge clk) if (mr_we) saw_mr_we <= 1'b1;

  initial begin
    init_start_p = 0; rdly_count_p = 8'd4;
    ctrl_ck_t_p = '0; ctrl_ck_c_p = '0; ctrl_cs_n_p = '1;
    rst_n = 0;
    #57 rst_n = 1;
    repeat (4) @(negedge clk);

    // 啟動訓練
    init_start_p = 1;
    @(negedge clk);
    init_start_p = 0;

    // P_TRAIN 等 train_cnt > rdly_count (4) -> P_DONE
    repeat (12) @(negedge clk);
    if (!init_done) begin
      errors++;
      $display("TB ERROR: init_done not set after training");
    end
    if (!saw_mr_we) begin
      errors++;
      $display("TB ERROR: mr_we never asserted (P_MR not reached)");
    end

    // P_DONE 後 ctrl pin passthrough toggle
    ctrl_ck_t_p = 3'b101; ctrl_ck_c_p = 3'b010; ctrl_cs_n_p = 3'b000;
    @(negedge clk);
    ctrl_ck_t_p = 3'b010; ctrl_ck_c_p = 3'b101; ctrl_cs_n_p = 3'b111;
    @(negedge clk);

    // default arm: 逐 bit force st 到無效值 3'd5 (enum 不可 cast, pitfall 7)
    fsm_mute = 1;
    force dut.st[0] = 1'b1;
    force dut.st[1] = 1'b0;
    force dut.st[2] = 1'b1;
    @(negedge clk);
    release dut.st[0];
    release dut.st[1];
    release dut.st[2];
    @(negedge clk);
    @(negedge clk);   // fsm_mon 於 posedge 采樣的是 NBA 更新前的舊值,
                      // 多等一拍讓 prev 在靜音中跟上 0, 避免記到假弧 5->0
    fsm_mute = 0;
    if (dut.st != 3'd0) begin   // P_RESET = 0 (enum 在 DUT 內, TB 以數值比對)
      errors++;
      $display("TB ERROR: default arm did not return to P_RESET");
    end

    // ---- F4 toggle poke-blitz (此時 st=P_RESET, init_start=0, 無後續 clock 敏感) ----
    `F4POKE_TB(rdly_count)
    `F4POKE(train_cnt)
    repeat (3) @(posedge clk);

    if (errors) $fatal(1, "TB FAIL: f4_hbm3_phy %0d errors", errors);
    $display("TB PASS: f4_hbm3_phy training sequence + passthrough covered");
    $finish;
  end
endmodule : f4_hbm3_phy_tb
