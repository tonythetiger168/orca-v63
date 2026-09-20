// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - Power Management Unit v1.0
// 每電源域獨立低功耗 FSM: ON -> IDLE -> RETENTION -> OFF, 唤醒源管理,
// 時脈閘控 / 電源開關 / 隔離 / 保持 / DVFS 電壓頻率選擇。
`include "orca_pkg.sv"

module orca_pmu
  import orca_pkg::*;
#(
  parameter int NUM_PD = 4      // 電源域數: 0=CPU tile, 1=AI tile, 2=NOC, 3=IO
)(
  input  logic clk, rst_n,
  input  logic [NUM_PD-1:0] pd_sleep_req,   // 軟體/硬體睡眠請求 (每域)
  input  logic [NUM_PD-1:0] pd_force_on,    // 強制喚醒 (喚醒源)
  input  logic [NUM_PD-1:0] pd_busy,        // 域仍有工作 (禁止進深睡)
  input  logic [NUM_PD-1:0] pd_wake_evt,    // 唤醒事件
  output pwrm_state_t [NUM_PD-1:0] pd_state,
  output logic [NUM_PD-1:0] pd_clk_gate,    // 時脈閘控使能 (低有效概念: 1=gate)
  output logic [NUM_PD-1:0] pd_iso,         // 隔離使能
  output logic [NUM_PD-1:0] pd_ret_save,    // retention 儲存脈衝
  output logic [NUM_PD-1:0] pd_ret_restore, // retention 恢復脈衝
  output logic [NUM_PD-1:0] pd_pwr_sleep,   // 電源開關 sleep
  input  logic [NUM_PD-1:0] pd_pwr_ack,     // 電源開關 ack
  output logic [NUM_PD-1:0] pd_pwr_good,
  // DVFS
  input  logic [2:0] dvfs_req,              // 0..4 效能點
  output logic [2:0] dvfs_lvl,              // 當前電壓檔
  output logic [2:0] dvfs_freq_sel
);
  // 每域 FSM
  genvar g;
  generate
    for (g = 0; g < NUM_PD; g++) begin : g_pd
      pwrm_state_t st, st_n;
      logic [3:0] idle_cnt;
      logic       entry_req, wake_req, can_deep;

      assign pd_state[g]        = st;
      assign pd_clk_gate[g]     = (st == ST_IDLE) || (st == ST_RETENTION) || (st == ST_OFF);
      assign pd_iso[g]          = (st == ST_OFF);
      assign pd_ret_save[g]     = (st_n == ST_RETENTION) && (st == ST_IDLE);
      assign pd_ret_restore[g]  = (st == ST_RETENTION) && (st_n == ST_ON);
      assign pd_pwr_sleep[g]    = (st == ST_OFF);
      assign pd_pwr_good[g]     = pd_pwr_ack[g];
      assign entry_req          = pd_sleep_req[g];
      assign wake_req           = pd_force_on[g] || pd_wake_evt[g];
      assign can_deep           = !pd_busy[g];

      // 深睡判定: 請求 + 無 busy; IDLE 逾時進 RETENTION
      wire go_retention = entry_req && can_deep && (idle_cnt == 4'hF);
      wire go_off       = entry_req && can_deep && (st == ST_RETENTION);

      always_comb begin
        st_n = st;
        unique case (st)
          ST_ON:        if (entry_req && can_deep) st_n = ST_IDLE;
          ST_IDLE:      if (wake_req)             st_n = ST_ON;
                        else if (go_retention)      st_n = ST_RETENTION;
          ST_RETENTION: if (wake_req)             st_n = ST_ON;
                        else if (go_off)            st_n = ST_OFF;
          ST_OFF:       if (wake_req && pd_pwr_ack[g]) st_n = ST_ON;
          // 防禦性 default: 2-bit enum 僅 4 合法態, 結構不可達 (COV_EXCL)
          /* verilator coverage_off */
          default: st_n = ST_ON;
          /* verilator coverage_on */
        endcase
      end

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          st <= ST_ON; idle_cnt <= '0;
        end else begin
          st <= st_n;
          if (st == ST_IDLE && entry_req && !wake_req)
            idle_cnt <= idle_cnt + 1'b1;
          else
            idle_cnt <= '0;
        end
      end
    end
  endgenerate

  // DVFS: 5 檔效能點 (電壓 + 頻率), 請求直通 (簡化, 實作含轉換延遲)
  logic [2:0] dvfs_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) dvfs_q <= 3'd2;   // 預設中檔
    else if (dvfs_req <= 3'd4)    dvfs_q <= dvfs_req;
  end
  assign dvfs_lvl      = dvfs_q;
  assign dvfs_freq_sel = dvfs_q;
endmodule : orca_pmu
