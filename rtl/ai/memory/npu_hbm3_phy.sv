// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// HBM3 PHY stub: 初始化/ZQ/read-leveling 訓練序列, mode register 介面
module npu_hbm3_phy
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  logic init_start,
  output logic init_done,
  output logic [HBM3_STACKS-1:0] ck_t, ck_c,
  output logic [HBM3_STACKS-1:0] cs_n,
  input  logic [7:0]  rdly_count,   /*verilator coverage_off*/ // mr_addr/mr_wdata tie-off stub
  output logic [15:0] mr_addr,
  output logic [31:0] mr_wdata,  /*verilator coverage_on*/
  output logic        mr_we,
  // ORCA v6.3.3: controller pin passthrough (new ports, default binding).
  // After training completes (P_DONE) the PHY forwards npu_hbm3_ctrl's
  // command/clock pins to the HBM pins; during reset/training it drives its
  // own training pattern (ck held, cs_n deasserted-high).
  input  logic [HBM3_STACKS-1:0] ctrl_ck_t,
  input  logic [HBM3_STACKS-1:0] ctrl_ck_c,
  input  logic [HBM3_STACKS-1:0] ctrl_cs_n
);
  import orca_pkg::*;
  typedef enum logic [2:0] {P_RESET, P_ZQ, P_MR, P_TRAIN, P_DONE} pst_t;
  pst_t st;
  logic [7:0] train_cnt;
  assign init_done = (st == P_DONE);
  assign ck_t = (st == P_DONE) ? ctrl_ck_t : {HBM3_STACKS{1'b0}};
  assign ck_c = (st == P_DONE) ? ctrl_ck_c : {HBM3_STACKS{1'b1}};
  assign cs_n = (st == P_DONE) ? ctrl_cs_n : {HBM3_STACKS{1'b1}};
  assign mr_we   = (st == P_MR);
  assign mr_addr = 16'h0;
  assign mr_wdata = 32'h0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin st <= P_RESET; train_cnt <= '0; end
    else begin
      unique case (st)
        P_RESET: if (init_start) st <= P_ZQ;
        P_ZQ:    st <= P_MR;
        P_MR:    st <= P_TRAIN;
        P_TRAIN: begin
          train_cnt <= train_cnt + 1'b1;
          if (train_cnt > rdly_count) st <= P_DONE;
        end
        P_DONE: ;
        default: st <= P_RESET;
      endcase
    end
  end
endmodule : npu_hbm3_phy
