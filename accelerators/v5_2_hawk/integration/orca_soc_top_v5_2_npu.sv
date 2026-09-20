//============================================================================
// ORCA v5.2 X++ SoC — Hawk NPU Integration Module
// Connects Hawk NPU (RVV-256 + FMX2 + Transformer Block) to AXI4 crossbar
//============================================================================
`ifndef ORCA_SOC_TOP_V5_2_NPU_SV
`define ORCA_SOC_TOP_V5_2_NPU_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_soc_top_v5_2_npu #
( parameter int VLEN  = 256
, parameter int LANES = 8  )  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// RVV-256 Interface (from vector unit)
// --------------------------------------------------------------------------
, input  logic [VLEN-1:0]     vec_operand_a
, input  logic [VLEN-1:0]     vec_operand_b
, input  logic [VLEN-1:0]     vec_operand_c
, input  logic [4:0]          vec_rd
, input  logic [4:0]          vec_rs1
, input  logic [4:0]          vec_rs2
, input  logic                vec_valid
, output logic                vec_ready
// --------------------------------------------------------------------------
// FMX2 Instruction (from custom decoder)
// --------------------------------------------------------------------------
, input  logic [31:0]         fmx2_instr
, input  logic                fmx2_valid
, output logic                fmx2_ready
// --------------------------------------------------------------------------
// Transformer Block Command
// --------------------------------------------------------------------------
, input  logic [63:0]         xfmr_cmd
, input  logic                xfmr_cmd_valid
, output logic                xfmr_cmd_ready
// --------------------------------------------------------------------------
// AXI4 Memory Interface (256-bit wide)
// --------------------------------------------------------------------------
, output logic [63:0]         m_axi_araddr
, output logic                m_axi_arvalid
, input  logic                m_axi_arready
, input  logic [255:0]        m_axi_rdata
, input  logic                m_axi_rvalid
, output logic                m_axi_rready
, output logic [63:0]         m_axi_awaddr
, output logic                m_axi_awvalid
, input  logic                m_axi_awready
, output logic [255:0]        m_axi_wdata
, output logic [31:0]         m_axi_wstrb
, output logic                m_axi_wvalid
, input  logic                m_axi_wready
// --------------------------------------------------------------------------
// Interrupt
// --------------------------------------------------------------------------
, output logic                npu_done_irq
, output logic [63:0]         npu_ops_counter
, output logic                xfmr_busy  );
  orca_npu_v5_2 #    ( .VLEN(256)
, .LANES(8)
, .NUM_ARRAYS(4)
, .ARRAY_DIM_X(32)
, .ARRAY_DIM_Y(32)
, .ACC_WIDTH(32)
, .TILE_SIZE(8192)
, .DATA_WIDTH(8)
, .AXI_DATA_W(256)    ) u_hawk (
.clk            (clk)
, .rst_n          (rst_n)
, .vec_operand_a  (vec_operand_a)
, .vec_operand_b  (vec_operand_b)
, .vec_operand_c  (vec_operand_c)
, .vec_rd         (vec_rd)
, .vec_rs1        (vec_rs1)
, .vec_rs2        (vec_rs2)
, .vec_valid      (vec_valid)
, .vec_ready      (vec_ready)
, .fmx2_instr     (fmx2_instr)
, .fmx2_valid     (fmx2_valid)
, .fmx2_ready     (fmx2_ready)
, .xfmr_cmd       (xfmr_cmd)
, .xfmr_cmd_valid (xfmr_cmd_valid)
, .xfmr_cmd_ready (xfmr_cmd_ready)
, .m_axi_araddr   (m_axi_araddr)
, .m_axi_arvalid  (m_axi_arvalid)
, .m_axi_arready  (m_axi_arready)
, .m_axi_rdata    (m_axi_rdata)
, .m_axi_rvalid   (m_axi_rvalid)
, .m_axi_rready   (m_axi_rready)
, .m_axi_awaddr   (m_axi_awaddr)
, .m_axi_awvalid  (m_axi_awvalid)
, .m_axi_awready  (m_axi_awready)
, .m_axi_wdata    (m_axi_wdata)
, .m_axi_wstrb    (m_axi_wstrb)
, .m_axi_wvalid   (m_axi_wvalid)
, .m_axi_wready   (m_axi_wready)
, .npu_done_irq   (npu_done_irq)
, .npu_ops_counter(npu_ops_counter)
, .xfmr_busy      (xfmr_busy)  );
endmodule
`endif
