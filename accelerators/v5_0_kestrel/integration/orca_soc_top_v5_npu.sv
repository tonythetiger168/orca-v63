//============================================================================
// ORCA v5.0 X SoC — Kestrel NPU Integration Module
// Connects Kestrel NPU to AXI4 crossbar as memory-mapped peripheral + DMA master
//============================================================================
`ifndef ORCA_SOC_TOP_V5_NPU_SV
`define ORCA_SOC_TOP_V5_NPU_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_soc_top_v5_npu (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// AXI4 slave interface from CPU (memory-mapped config)
// --------------------------------------------------------------------------
, input  logic        s_axi_awvalid
, output logic        s_axi_awready
, input  logic [63:0] s_axi_awaddr
, input  logic        s_axi_wvalid
, output logic        s_axi_wready
, input  logic [63:0] s_axi_wdata
, input  logic [7:0]  s_axi_wstrb
, output logic        s_axi_bvalid
, input  logic        s_axi_bready
, output logic [1:0]  s_axi_bresp
, input  logic        s_axi_arvalid
, output logic        s_axi_arready
, input  logic [63:0] s_axi_araddr
, output logic        s_axi_rvalid
, input  logic        s_axi_rready
, output logic [63:0] s_axi_rdata
, output logic [1:0]  s_axi_rresp
// --------------------------------------------------------------------------
// AXI4 master interface to crossbar (DMA)
// --------------------------------------------------------------------------
, output logic        m_axi_awvalid
, input  logic        m_axi_awready
, output logic [63:0] m_axi_awaddr
, output logic        m_axi_wvalid
, input  logic        m_axi_wready
, output logic [63:0] m_axi_wdata
, output logic [7:0]  m_axi_wstrb
, input  logic        m_axi_bvalid
, output logic        m_axi_bready
, input  logic [1:0]  m_axi_bresp
, output logic        m_axi_arvalid
, input  logic        m_axi_arready
, output logic [63:0] m_axi_araddr
, input  logic        m_axi_rvalid
, output logic        m_axi_rready
, input  logic [63:0] m_axi_rdata
, input  logic [1:0]  m_axi_rresp
// --------------------------------------------------------------------------
// Interrupt to PLIC
// --------------------------------------------------------------------------
, output logic        npu_irq
, output logic [63:0] npu_ops_counter  );
// NPU instance
orca_npu_v5 #    ( .MAC_UNITS(8)
, .ACC_WIDTH(32)
, .WEIGHT_DEPTH(1024)
, .ACTIVATION_DEPTH(1024)
, .DATA_WIDTH(8)    ) u_npu (
.clk          (clk)
, .rst_n        (rst_n)
// Config interface (AXI-Lite subset)
, .cfg_awvalid  (s_axi_awvalid)
, .cfg_awready  (s_axi_awready)
, .cfg_awaddr   (s_axi_awaddr[15:0])
, .cfg_wvalid   (s_axi_wvalid)
, .cfg_wready   (s_axi_wready)
, .cfg_wdata    (s_axi_wdata)
, .cfg_wstrb    (s_axi_wstrb)
, .cfg_bvalid   (s_axi_bvalid)
, .cfg_bready   (s_axi_bready)
, .cfg_bresp    (s_axi_bresp)
, .cfg_arvalid  (s_axi_arvalid)
, .cfg_arready  (s_axi_arready)
, .cfg_araddr   (s_axi_araddr[15:0])
, .cfg_rvalid   (s_axi_rvalid)
, .cfg_rready   (s_axi_rready)
, .cfg_rdata    (s_axi_rdata)
, .cfg_rresp    (s_axi_rresp)
// DMA interface (passthrough to AXI master)
, .m_axi_araddr (m_axi_araddr)
, .m_axi_arvalid(m_axi_arvalid)
, .m_axi_arready(m_axi_arready)
, .m_axi_rdata  (m_axi_rdata)
, .m_axi_rvalid (m_axi_rvalid)
, .m_axi_rready (m_axi_rready)
, .m_axi_rresp  (m_axi_rresp)
, .m_axi_awaddr (m_axi_awaddr)
, .m_axi_awvalid(m_axi_awvalid)
, .m_axi_awready(m_axi_awready)
, .m_axi_wdata  (m_axi_wdata)
, .m_axi_wstrb  (m_axi_wstrb)
, .m_axi_wvalid (m_axi_wvalid)
, .m_axi_wready (m_axi_wready)
, .m_axi_bvalid (m_axi_bvalid)
, .m_axi_bready (m_axi_bready)
, .m_axi_bresp  (m_axi_bresp)
// Status
, .npu_irq      (npu_irq)
, .npu_ops_counter(npu_ops_counter)
// Unused direct memory interface
);
endmodule
`endif
