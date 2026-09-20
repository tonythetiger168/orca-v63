// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - low power v1.0
`include "orca_pkg.sv"

// 整合式時脈閘控單元 (ICG): 低電平鎖存 enable, 下降沿後閘控
// en=0 時 clk_out 停在高電平 (標準 ICG 行為, 無毛刺)
module clock_gate (
  input  logic clk,
  input  logic en,
  input  logic test_en,     // DFT 測試使能 (強制開啟)
  output logic clk_out
);
  import orca_pkg::*;
  logic en_latch;
  always_latch begin
    if (!clk) en_latch <= en | test_en;
  end
  assign clk_out = clk & en_latch;
endmodule : clock_gate

// 電源開關 (header switch 行為模型): sleep 時切斷虛擬電源軌
// 回傳 ack 供 PMU 確認域電壓已穩定 (唤醒時序)
module power_switch (
  input  logic clk,
  input  logic rst_n,
  input  logic sleep,      // 1=斷電, 0=上電
  output logic power_on,   // 域電源良好
  output logic ack
);
  import orca_pkg::*;
  logic [3:0] cnt;
  typedef enum logic [1:0] {SW_ON, SW_RAMP_DN, SW_OFF, SW_RAMP_UP} sw_t;
  sw_t st;
  assign power_on = (st == SW_ON);
  assign ack      = (st == SW_ON) || (st == SW_OFF);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= SW_ON; cnt <= '0; end
    else begin
      cnt <= cnt + 1'b1;
      unique case (st)
        SW_ON:      if (sleep && cnt == 4'hF) st <= SW_RAMP_DN;
        SW_RAMP_DN: if (cnt == 4'h3) st <= SW_OFF;
        SW_OFF:     if (!sleep && cnt == 4'hF) st <= SW_RAMP_UP;
        SW_RAMP_UP: if (cnt == 4'h3) st <= SW_ON;
        // 防禦性 default: 2-bit enum 僅 4 合法態, 結構不可達 (COV_EXCL)
        /* verilator coverage_off */
        default: st <= SW_ON;
        /* verilator coverage_on */
      endcase
    end
  end
endmodule : power_switch

// 隔離單元: 域斷電時把輸出鉗位到常數, 避免未知態傳播
module isolation_cell #(
  parameter int W = 32,
  parameter logic [W-1:0] CLAMP = '0
)(
  input  logic [W-1:0] data,
  input  logic         iso_en,   // 1=隔離
  output logic [W-1:0] data_iso
);
  assign data_iso = iso_en ? CLAMP : data;
endmodule : isolation_cell

// 保持寄存器 (retention): 斷電前把主寄存器拷入影子寄存器, 上電後恢復
module retention_reg #(
  parameter int W = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic save,      // 進入 retention 前儲存
  input  logic restore,   // 唤醒後恢復
  input  logic [W-1:0] d,
  output logic [W-1:0] q
);
  logic [W-1:0] master, shadow;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin master <= '0; shadow <= '0; end
    else begin
      if (save)    shadow <= master;
      if (restore) master <= shadow;
      else         master <= d;
    end
  end
  assign q = master;
endmodule : retention_reg
