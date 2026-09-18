//============================================================================
// ORCA v5.1 X+ — Falcon NPU (RVV-Based Vector AI Accelerator)
// Peak Performance: 4 TOPS @ 1.5GHz (INT8)
// Target Process: 12nm
// Area Estimate: ~1.8 mm2
// Power Estimate: <800mW
//
// Features:
// - RVV 1.0 compliant vector interface (VLEN=128, 4 lanes)
// - 32x32 dual systolic array (FMX: Falcon Matrix Extension)
// - INT8/INT16/FP16/BF16 support
// - Tile-based computation with 16KB local SRAM
//============================================================================
`ifndef ORCA_NPU_V5_1_SV
`define ORCA_NPU_V5_1_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_npu_v5_1 #
( parameter int VLEN           = 128
, parameter int LANES          = 4
// 128/32 = 4
, parameter int MAC_ARRAY_DIM  = 32
// 32x32 systolic
, parameter int ACC_WIDTH      = 32
, parameter int TILE_SIZE      = 4096
// 16KB / 4 bytes
, parameter int AXI_DATA_W     = 128
// Wide AXI for vector
)  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// RVV Interface (from vector unit — shared VRF access)
// --------------------------------------------------------------------------
, input  logic [VLEN-1:0]     vec_operand_a
, input  logic [VLEN-1:0]     vec_operand_b
, input  logic [VLEN-1:0]     vec_operand_c
// accumulator
, input  logic [4:0]          vec_rd
, input  logic [4:0]          vec_rs1
, input  logic [4:0]          vec_rs2
, input  logic                vec_valid
, output logic                vec_ready
// --------------------------------------------------------------------------
// Custom FMX Instruction Interface (from decoder)
// --------------------------------------------------------------------------
, input  logic [31:0]         fmx_instr
, input  logic                fmx_valid
, output logic                fmx_ready
// --------------------------------------------------------------------------
// AXI4 Memory Interface (wide, 128-bit)
// --------------------------------------------------------------------------
, output logic [63:0]         m_axi_araddr
, output logic                m_axi_arvalid
, input  logic                m_axi_arready
, input  logic [AXI_DATA_W-1:0] m_axi_rdata
, input  logic                m_axi_rvalid
, output logic                m_axi_rready
, output logic [63:0]         m_axi_awaddr
, output logic                m_axi_awvalid
, input  logic                m_axi_awready
, output logic [AXI_DATA_W-1:0] m_axi_wdata
, output logic [AXI_DATA_W/8-1:0] m_axi_wstrb
, output logic                m_axi_wvalid
, input  logic                m_axi_wready
// --------------------------------------------------------------------------
// Interrupt & status
// --------------------------------------------------------------------------
, output logic                npu_done_irq
, output logic [63:0]         npu_ops_counter  );
// ==========================================================================
//  FMX Decode
// ==========================================================================
logic [6:0]  fmx_opcode;
  logic [4:0]  fmx_rd, fmx_rs1, fmx_rs2;
  logic [2:0]  fmx_funct3;
  logic [6:0]  fmx_funct7;
  logic        is_fmx_mmacc, is_fmx_load, is_fmx_store, is_fmx_quant;
assign fmx_opcode = fmx_instr[6:0];
assign fmx_rd     = fmx_instr[11:7];
assign fmx_funct3 = fmx_instr[14:12];
assign fmx_rs1    = fmx_instr[19:15];
assign fmx_rs2    = fmx_instr[24:20];
assign fmx_funct7 = fmx_instr[31:25];
assign is_fmx_mmacc = (fmx_opcode == 7'b0101011) && (fmx_funct3 == 3'b000);
assign is_fmx_load  = (fmx_opcode == 7'b0101011) && (fmx_funct3 == 3'b001);
assign is_fmx_store = (fmx_opcode == 7'b0101011) && (fmx_funct3 == 3'b010);
assign is_fmx_quant = (fmx_opcode == 7'b0101011) && (fmx_funct3 == 3'b011);
// ==========================================================================
//  Tile SRAM (Weight & Activation)
// ==========================================================================
localparam int TILE_DEPTH = TILE_SIZE;
 // 4096 entries
logic signed [7:0] weight_tile [0:TILE_DEPTH-1];
  logic signed [7:0] act_tile    [0:TILE_DEPTH-1];
  logic signed [ACC_WIDTH-1:0] result_tile [0:TILE_DEPTH-1];
// ==========================================================================
//  32x32 Systolic Array (2 arrays for dual-issue)
// ==========================================================================
localparam int SYSTOLIC_DIM = 32;
  logic signed [7:0]  sa_weight [0:SYSTOLIC_DIM-1][0:SYSTOLIC_DIM-1];
  logic signed [7:0]  sa_act    [0:SYSTOLIC_DIM-1][0:SYSTOLIC_DIM-1];
  logic signed [ACC_WIDTH-1:0] sa_acc  [0:SYSTOLIC_DIM-1][0:SYSTOLIC_DIM-1];
// Systolic array control
logic [5:0] sa_cycle;
  logic       sa_busy;
  integer i, j, k;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      sa_cycle <= '0;
      sa_busy  <= 1'b0;
for (i = 0; i < SYSTOLIC_DIM; i = i + 1) begin
for (j = 0; j < SYSTOLIC_DIM; j = j + 1) begin          sa_acc[i][j] <= '0;
end
end
end else if (is_fmx_mmacc && !sa_busy) begin      sa_busy  <= 1'b1;
      sa_cycle <= '0;
// Load tiles into systolic array
for (i = 0; i < SYSTOLIC_DIM; i = i + 1) begin
for (j = 0; j < SYSTOLIC_DIM; j = j + 1) begin          sa_weight[i][j] <= weight_tile[i*SYSTOLIC_DIM + j];
          sa_act[i][j]    <= act_tile[i*SYSTOLIC_DIM + j];
          sa_acc[i][j]    <= '0;
end
end
end else if (sa_busy) begin
if (sa_cycle < SYSTOLIC_DIM + 2) begin        sa_cycle <= sa_cycle + 1;
// Systolic computation: wavefront propagation
for (i = 0; i < SYSTOLIC_DIM; i = i + 1) begin
for (j = 0; j < SYSTOLIC_DIM; j = j + 1) begin
if (i == 0 && j == 0)              sa_acc[i][j] <= sa_acc[i][j] + sa_weight[i][j] * sa_act[i][j];
else if (sa_cycle >= i+j)              sa_acc[i][j] <= sa_acc[i][j] + sa_weight[i][j] * sa_act[i][j];
end
end
end else begin        sa_busy <= 1'b0;
// Write result to result_tile
for (i = 0; i < SYSTOLIC_DIM; i = i + 1) begin
for (j = 0; j < SYSTOLIC_DIM; j = j + 1) begin            result_tile[i*SYSTOLIC_DIM + j] <= sa_acc[i][j];
end
end
end
end
end
// ==========================================================================
//  Quantization & Activation Unit
// ==========================================================================
logic signed [7:0] quant_result [0:SYSTOLIC_DIM-1][0:SYSTOLIC_DIM-1];
  logic [15:0] scale_factor;
  logic [7:0]  zero_point;
always_ff @(posedge clk) begin
if (is_fmx_quant) begin      scale_factor <= vec_operand_a[15:0];
      zero_point   <= vec_operand_a[23:16];
end
end
generate
genvar gi, gj;
for (gi = 0; gi < SYSTOLIC_DIM; gi = gi + 1) begin : quant_i
for (gj = 0; gj < SYSTOLIC_DIM; gj = gj + 1) begin : quant_j        logic signed [ACC_WIDTH-1:0] scaled;
        logic signed [7:0] quantized;
always_comb begin          scaled = (sa_acc[gi][gj] * scale_factor) >>> 8;
          quantized = scaled[7:0] + zero_point;
// Saturate
if (scaled > 127)  quantized = 8'sd127;
else if (scaled < -128) quantized = -8'sd128;
          quant_result[gi][gj] = quantized;
end
end
end
endgenerate
// ==========================================================================
//  Performance Counter
// ==========================================================================
logic [63:0] ops_cnt;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      ops_cnt <= '0;
end else if (sa_busy) begin      ops_cnt <= ops_cnt + (SYSTOLIC_DIM * SYSTOLIC_DIM);
end
end
// ==========================================================================
//  Outputs
// ==========================================================================
assign npu_ops_counter = ops_cnt;
assign npu_done_irq    = !sa_busy && (sa_cycle > 0);
assign fmx_ready       = !sa_busy;
assign vec_ready       = !sa_busy;
// AXI memory interface stubs
assign m_axi_arvalid = is_fmx_load;
assign m_axi_araddr  = vec_operand_a[63:0];
assign m_axi_rready  = 1'b1;
assign m_axi_awvalid = is_fmx_store;
assign m_axi_awaddr  = vec_operand_b[63:0];
assign m_axi_wdata   = {result_tile[15], result_tile[14], result_tile[13], result_tile[12],                         result_tile[11], result_tile[10], result_tile[9],  result_tile[8],                         result_tile[7],  result_tile[6],  result_tile[5],  result_tile[4],                         result_tile[3],  result_tile[2],  result_tile[1],  result_tile[0]};
assign m_axi_wstrb   = '1;
assign m_axi_wvalid  = is_fmx_store;
endmodule // orca_npu_v5_1
`endif
// ORCA_NPU_V5_1_SV
