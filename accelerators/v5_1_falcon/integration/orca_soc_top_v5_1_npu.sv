//============================================================================
// ORCA v5.1 X+ SoC — Falcon NPU Integration Module
// Connects Falcon NPU (RVV + FMX) to vector unit and AXI4 crossbar
//============================================================================
`ifndef ORCA_SOC_TOP_V5_1_NPU_SV
`define ORCA_SOC_TOP_V5_1_NPU_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_soc_top_v5_1_npu #
( parameter int VLEN  = 128
, parameter int LANES = 4  )  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// RVV Interface (from vector unit)
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
// FMX Instruction (from custom decoder)
// --------------------------------------------------------------------------
, input  logic [31:0]         fmx_instr
, input  logic                fmx_valid
, output logic                fmx_ready
// --------------------------------------------------------------------------
// AXI4 Memory Interface (128-bit wide)
// --------------------------------------------------------------------------
, output logic [63:0]         m_axi_araddr
, output logic                m_axi_arvalid
, input  logic                m_axi_arready
, input  logic [127:0]        m_axi_rdata
, input  logic                m_axi_rvalid
, output logic                m_axi_rready
, output logic [63:0]         m_axi_awaddr
, output logic                m_axi_awvalid
, input  logic                m_axi_awready
, output logic [127:0]        m_axi_wdata
, output logic [15:0]         m_axi_wstrb
, output logic                m_axi_wvalid
, input  logic                m_axi_wready
// --------------------------------------------------------------------------
// Interrupt
// --------------------------------------------------------------------------
, output logic                npu_done_irq
, output logic [63:0]         npu_ops_counter  );
  orca_npu_v5_1 #    ( .VLEN(128)
, .LANES(4)
, .MAC_ARRAY_DIM(32)
, .ACC_WIDTH(32)
, .TILE_SIZE(4096)
, .AXI_DATA_W(128)    ) u_falcon (
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
, .fmx_instr      (fmx_instr)
, .fmx_valid      (fmx_valid)
, .fmx_ready      (fmx_ready)
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
, .npu_ops_counter(npu_ops_counter)  );
endmodule
`endif
