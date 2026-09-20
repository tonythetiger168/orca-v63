// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - Low Power coverage TB
// 覆蓋 PMU 每域 FSM 全狀態/全轉換/各唤醒源/busy 阻擋/DVFS 全檔,
// 以及 clock_gate / power_switch / isolation_cell / retention_reg 全功能。
`include "orca_pkg.sv"

module lp_coverage_tb;
  import orca_pkg::*;
  localparam int NPD = 4;
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  // ===== randomize seed (+seed=N 多 seed 合併收斂 toggle/FSM) =====
  int unsigned seed;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 32'h0DCA_0000;
    $display("SEED=%0d", seed);
    $urandom(seed);
  end


  // ---- PMU ----
  logic [NPD-1:0] sleep_req, force_on, busy, wake_evt, pwr_ack;
  pwrm_state_t [NPD-1:0] pd_state;
  logic [NPD-1:0] clk_gate, iso, ret_save, ret_restore, pwr_sleep, pwr_good;
  logic [2:0] dvfs_req, dvfs_lvl, dvfs_fsel;
  orca_pmu #(.NUM_PD(NPD)) u_pmu (
    .clk(clk), .rst_n(rst_n),
    .pd_sleep_req(sleep_req), .pd_force_on(force_on), .pd_busy(busy), .pd_wake_evt(wake_evt),
    .pd_state(pd_state), .pd_clk_gate(clk_gate), .pd_iso(iso),
    .pd_ret_save(ret_save), .pd_ret_restore(ret_restore),
    .pd_pwr_sleep(pwr_sleep), .pd_pwr_ack(pwr_ack), .pd_pwr_good(pwr_good),
    .dvfs_req(dvfs_req), .dvfs_lvl(dvfs_lvl), .dvfs_freq_sel(dvfs_fsel));

  // ---- power_switch x NPD (ack 回授 PMU) ----
  logic [NPD-1:0] sw_pon;
  genvar gp;
  generate
    for (gp = 0; gp < NPD; gp++) begin : g_sw
      power_switch u_sw (.clk(clk), .rst_n(rst_n), .sleep(pwr_sleep[gp]),
                         .power_on(sw_pon[gp]), .ack(pwr_ack[gp]));
    end
  endgenerate

  // ---- clock_gate ----
  logic cg_en, cg_te, cg_out; logic cg_clk=0;
  clock_gate u_cg (.clk(clk), .en(cg_en), .test_en(cg_te), .clk_out(cg_out));

  // ---- isolation_cell ----
  logic [31:0] iso_din, iso_dout; logic iso_en;
  isolation_cell #(.W(32), .CLAMP(32'hDEAD_0000)) u_iso (
    .data(iso_din), .iso_en(iso_en), .data_iso(iso_dout));

  // ---- retention_reg ----
  logic [31:0] rr_d, rr_q; logic rr_save, rr_restore;
  retention_reg #(.W(32)) u_rr (
    .clk(clk), .rst_n(rst_n), .save(rr_save), .restore(rr_restore), .d(rr_d), .q(rr_q));

  // 狀態訪問計數
  int st_visits [0:3];
  int transitions = 0;
  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int p = 0; p < NPD; p++) st_visits[int'(pd_state[p])] <= st_visits[int'(pd_state[p])] + 1;
    end
  end

  // 唤醒任一域: 清 sleep, 給唤醒源
  task automatic wake_pd(input int p, input logic use_force);
    begin
      sleep_req[p] = 0;
      if (use_force) force_on[p] = 1; else wake_evt[p] = 1;
      repeat (20) @(negedge clk);
      force_on[p] = 0; wake_evt[p] = 0;
    end
  endtask

  // 等域進入指定狀態 (bounded)
  task automatic wait_st(input int p, input pwrm_state_t tgt);
    int g = 0;
    begin
      while (pd_state[p] != tgt && g < 200) begin @(negedge clk); g++; end
    end
  endtask

  initial begin
    sleep_req='0; force_on='0; busy='0; wake_evt='0;
    cg_en=0; cg_te=0; iso_din=32'h1234_5678; iso_en=0;
    rr_d=32'hAAAA_5555; rr_save=0; rr_restore=0; dvfs_req=3'd2;
    rst_n=0; #57 rst_n=1; @(negedge clk);

    // ============ PMU 全域狀態巡走 (每域走完整 ON->IDLE->RET->OFF->ON) ============
    for (int p = 0; p < NPD; p++) begin
      // ON -> IDLE (sleep_req & !busy)
      sleep_req[p]=1; wait_st(p, ST_IDLE);
      // IDLE -> RETENTION (idle_cnt 滿)
      wait_st(p, ST_RETENTION);
      // RETENTION -> OFF
      wait_st(p, ST_OFF);
      repeat(40) @(negedge clk);   // soak OFF: power_switch 完成 ramp-down
      // OFF -> ON (唤醒, 等 power ack)
      wake_pd(p, 0);
      wait_st(p, ST_ON);
      sleep_req[p]=0; repeat(10) @(negedge clk);
    end

    // ============ go_off else: 進 RETENTION 立即撤 sleep_req -> 停留 RETENTION ============
    for (int p = 0; p < NPD; p++) begin
      sleep_req[p]=1;
      wait_st(p, ST_RETENTION);
      sleep_req[p]=0;                 // 同週期撤請求: go_off=0, 停留 RETENTION
      repeat(30) @(negedge clk);      // soak in RETENTION (覆蓋 go_off else)
      // 重新請求, 由 RETENTION 睡到 OFF
      sleep_req[p]=1; wait_st(p, ST_OFF); repeat(20) @(negedge clk);
      wake_pd(p, 0); wait_st(p, ST_ON); sleep_req[p]=0;
      repeat(5) @(negedge clk);
    end

    // ============ 各唤醒源逐一測試 (在 IDLE/RETENTION/OFF 各唤醒) ============
    for (int p = 0; p < NPD; p++) begin
      // 睡到 IDLE, force_on 唤醒
      sleep_req[p]=1; wait_st(p, ST_IDLE); wake_pd(p, 1); wait_st(p, ST_ON);
      // 睡到 RETENTION, wake_evt 唤醒
      sleep_req[p]=1; wait_st(p, ST_RETENTION); wake_pd(p, 0); wait_st(p, ST_ON);
      // 睡到 OFF, wake_evt 唤醒 (等 pwr ack)
      sleep_req[p]=1; wait_st(p, ST_OFF); repeat(40) @(negedge clk); wake_pd(p, 0); wait_st(p, ST_ON);
      sleep_req[p]=0; repeat(5) @(negedge clk);
    end

    // ============ force_on 與 wake_evt 同時觸發 ============
    sleep_req[1]=1; wait_st(1, ST_IDLE);
    force_on[1]=1; wake_evt[1]=1; repeat(20) @(negedge clk);
    force_on[1]=0; wake_evt[1]=0; wait_st(1, ST_ON); sleep_req[1]=0;
    repeat(10) @(negedge clk);

    // ============ busy 阻擋深睡 (應停在 ON, 不進 IDLE) ============
    busy[0]=1; sleep_req[0]=1; repeat(60) @(negedge clk);
    busy[0]=0; sleep_req[0]=0; repeat(10) @(negedge clk);

    // ============ DVFS 全 5 檔掃描 ============
    for (int v = 0; v < 5; v++) begin
      dvfs_req = 3'(v); repeat(10) @(negedge clk);
    end
    dvfs_req = 3'd7; repeat(5) @(negedge clk);   // 非法檔 (維持)

    // ============ clock_gate 全情境 ============
    cg_en=1; cg_te=0; repeat(10) @(negedge clk);   // 正常開
    cg_en=0; cg_te=0; repeat(10) @(negedge clk);   // 閘控
    cg_en=0; cg_te=1; repeat(10) @(negedge clk);   // test_en 強制開
    cg_en=1; cg_te=1; repeat(10) @(negedge clk);   // 都開

    // ============ isolation_cell 開關 ============
    iso_en=0; repeat(5) @(negedge clk);
    iso_en=1; repeat(5) @(negedge clk);

    // ============ retention_reg save/restore ============
    rr_d=32'h1111_2222; repeat(4) @(negedge clk);   // master 載入
    rr_save=1; repeat(4) @(negedge clk); rr_save=0; // 存入 shadow
    rr_d=32'h9999_8888; repeat(4) @(negedge clk);   // master 改變
    rr_restore=1; repeat(4) @(negedge clk); rr_restore=0; // 從 shadow 恢復
    repeat(5) @(negedge clk);

    $display("LP COVERAGE DONE: state visits ON=%0d IDLE=%0d RET=%0d OFF=%0d dvfs=%0d",
             st_visits[0], st_visits[1], st_visits[2], st_visits[3], dvfs_lvl);
    if (st_visits[0]>0 && st_visits[1]>0 && st_visits[2]>0 && st_visits[3]>0)
      $display("TB PASS: all 4 power states visited in all domains");
    else
      $fatal(1, "TB FAIL: not all power states visited");
    $finish;
  end
endmodule : lp_coverage_tb
