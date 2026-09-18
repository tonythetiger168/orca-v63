// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// PCIe Gen6 x16 控制器 stub: LTSSM + TLP 直通
module pcie_gen6
  import orca_pkg::*; (
  input  logic clk, rst_n,
  output logic pcie_tx_p, pcie_tx_n,
  input  logic pcie_rx_p, pcie_rx_n,
  input  logic pcie_refclk_p, pcie_refclk_n,
  input  logic [511:0] tlp_in,
  input  logic         tlp_in_valid,
  output logic         tlp_in_ready,
  output logic [511:0] tlp_out,
  output logic         tlp_out_valid
);
  typedef enum logic [2:0] {LT_DETECT, LT_POLL, LT_CONFIG, LT_L0, LT_RECOVERY} ltssm_t;
  ltssm_t lt;
  wire recovery = pcie_rx_p == pcie_rx_n;
  assign pcie_tx_p = (lt == LT_L0);
  assign pcie_tx_n = ~pcie_tx_p;
  assign tlp_in_ready  = (lt == LT_L0);
  assign tlp_out       = tlp_in;
  assign tlp_out_valid = tlp_in_valid && (lt == LT_L0);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) lt <= LT_DETECT;
    else begin
      unique case (lt)
        LT_DETECT:   lt <= LT_POLL;
        LT_POLL:     lt <= LT_CONFIG;
        LT_CONFIG:   lt <= LT_L0;
        LT_L0:       if (recovery) lt <= LT_RECOVERY;
        LT_RECOVERY: lt <= LT_DETECT;  /*verilator coverage_off*/
        default: lt <= LT_DETECT;  /*verilator coverage_on*/  // COV-EXEMPT: lt(3bit) 只取 5 個列舉值, defensive default 邏輯不可達
      endcase
    end
  end
endmodule : pcie_gen6
