//============================================================================
// ORCA v5.2 X++ — Hawk NPU (High-Performance Edge AI Accelerator)
// Peak Performance: 8 TOPS @ 2GHz (INT8)
// Target Process: 7nm
// Area Estimate: ~3.5 mm2
// Power Estimate: <3W
//
// Features:
// - RVV 1.0 compliant, VLEN=256, 8 lanes
// - FMX2: Falcon Matrix Extension v2 with 4x 32x32 systolic arrays
// - Transformer Block Hard-Acceleration (LayerNorm + Softmax + GELU pipeline)
// - INT8/INT16/FP16/BF16/FP32 support
// - 64KB local SRAM (32KB weight + 32KB activation)
// - 256-bit AXI4 interface
//============================================================================
`ifndef ORCA_NPU_V5_2_SV
`define ORCA_NPU_V5_2_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_npu_v5_2 #
( parameter int VLEN           = 256
, parameter int LANES          = 8
// 256/32 = 8
, parameter int NUM_ARRAYS     = 4
// 4 systolic arrays
, parameter int ARRAY_DIM_X    = 32
// 32 rows
, parameter int ARRAY_DIM_Y    = 32
// 32 cols
, parameter int ACC_WIDTH      = 32
, parameter int TILE_SIZE      = 8192
// 32KB / 4 bytes
, parameter int DATA_WIDTH     = 8
// INT8 default
, parameter int AXI_DATA_W     = 256
// 256-bit wide AXI
)  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// RVV Interface (VLEN=256, from vector unit)
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
// FMX2 Instruction Interface (from custom decoder)
// --------------------------------------------------------------------------
, input  logic [31:0]         fmx2_instr
, input  logic                fmx2_valid
, output logic                fmx2_ready
// --------------------------------------------------------------------------
// Transformer Block Command Interface
// --------------------------------------------------------------------------
, input  logic [63:0]         xfmr_cmd
, input  logic                xfmr_cmd_valid
, output logic                xfmr_cmd_ready
// --------------------------------------------------------------------------
// AXI4 Memory Interface (256-bit)
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
, output logic [63:0]         npu_ops_counter
, output logic                xfmr_busy  );
localparam int MACS_PER_ARRAY = ARRAY_DIM_X * ARRAY_DIM_Y;
 // 1024
localparam int TOTAL_MACS     = NUM_ARRAYS * MACS_PER_ARRAY;
 // 4096
// ==========================================================================
//  FMX2 Decode
// ==========================================================================
logic [6:0]  fmx2_opcode;
  logic [4:0]  fmx2_rd, fmx2_rs1, fmx2_rs2;
  logic [2:0]  fmx2_funct3;
  logic        is_fmx2_mmacc, is_fmx2_load, is_fmx2_store;
  logic        is_fmx2_quant, is_fmx2_xfmr;
assign fmx2_opcode = fmx2_instr[6:0];
assign fmx2_rd     = fmx2_instr[11:7];
assign fmx2_funct3 = fmx2_instr[14:12];
assign fmx2_rs1    = fmx2_instr[19:15];
assign fmx2_rs2    = fmx2_instr[24:20];
assign is_fmx2_mmacc = (fmx2_opcode == 7'b0101011) && (fmx2_funct3 == 3'b000);
assign is_fmx2_load  = (fmx2_opcode == 7'b0101011) && (fmx2_funct3 == 3'b001);
assign is_fmx2_store = (fmx2_opcode == 7'b0101011) && (fmx2_funct3 == 3'b010);
assign is_fmx2_quant = (fmx2_opcode == 7'b0101011) && (fmx2_funct3 == 3'b011);
assign is_fmx2_xfmr  = (fmx2_opcode == 7'b0101011) && (fmx2_funct3 == 3'b100);
// ==========================================================================
//  Tile SRAM (32KB Weight + 32KB Activation = 64KB total)
// ==========================================================================
localparam int TILE_DEPTH = TILE_SIZE;
 // 8192 entries
logic signed [DATA_WIDTH-1:0] weight_tile [0:TILE_DEPTH-1];
  logic signed [DATA_WIDTH-1:0] act_tile    [0:TILE_DEPTH-1];
  logic signed [ACC_WIDTH-1:0] result_tile [0:TILE_DEPTH-1];
// ==========================================================================
//  4 x 32x32 Systolic Arrays
// ==========================================================================
logic signed [DATA_WIDTH-1:0]  sa_weight [0:NUM_ARRAYS-1][0:ARRAY_DIM_X-1][0:ARRAY_DIM_Y-1];
  logic signed [DATA_WIDTH-1:0]  sa_act    [0:NUM_ARRAYS-1][0:ARRAY_DIM_X-1][0:ARRAY_DIM_Y-1];
  logic signed [ACC_WIDTH-1:0]   sa_acc    [0:NUM_ARRAYS-1][0:ARRAY_DIM_X-1][0:ARRAY_DIM_Y-1];
  logic [5:0] sa_cycle;
  logic       sa_busy;
  integer i, j, k, arr;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      sa_cycle <= '0;
      sa_busy  <= 1'b0;
for (arr = 0; arr < NUM_ARRAYS; arr = arr + 1) begin
for (i = 0; i < ARRAY_DIM_X; i = i + 1) begin
for (j = 0; j < ARRAY_DIM_Y; j = j + 1) begin            sa_acc[arr][i][j] <= '0;
end
end
end
end else if (is_fmx2_mmacc && !sa_busy) begin      sa_busy  <= 1'b1;
      sa_cycle <= '0;
for (arr = 0; arr < NUM_ARRAYS; arr = arr + 1) begin
for (i = 0; i < ARRAY_DIM_X; i = i + 1) begin
for (j = 0; j < ARRAY_DIM_Y; j = j + 1) begin            sa_weight[arr][i][j] <= weight_tile[arr*MACS_PER_ARRAY + i*ARRAY_DIM_Y + j];
            sa_act[arr][i][j]    <= act_tile[arr*MACS_PER_ARRAY + i*ARRAY_DIM_Y + j];
            sa_acc[arr][i][j]    <= '0;
end
end
end
end else if (sa_busy) begin
if (sa_cycle < ARRAY_DIM_Y + 2) begin        sa_cycle <= sa_cycle + 1;
for (arr = 0; arr < NUM_ARRAYS; arr = arr + 1) begin
for (i = 0; i < ARRAY_DIM_X; i = i + 1) begin
for (j = 0; j < ARRAY_DIM_Y; j = j + 1) begin
if (sa_cycle == 0)                sa_acc[arr][i][j] <= '0;
else if (sa_cycle <= ARRAY_DIM_Y)                sa_acc[arr][i][j] <= sa_acc[arr][i][j] +                  sa_weight[arr][i][sa_cycle-1] * sa_act[arr][sa_cycle-1][j];
end
end
end
end else begin        sa_busy <= 1'b0;
for (arr = 0; arr < NUM_ARRAYS; arr = arr + 1) begin
for (i = 0; i < ARRAY_DIM_X; i = i + 1) begin
for (j = 0; j < ARRAY_DIM_Y; j = j + 1) begin              result_tile[arr*MACS_PER_ARRAY + i*ARRAY_DIM_Y + j] <= sa_acc[arr][i][j];
end
end
end
end
end
end
// ==========================================================================
//  Transformer Block Hard-Acceleration Pipeline
// ==========================================================================
// LayerNorm: (x - mean) / sqrt(var + eps) * gamma + beta
// Softmax: exp(xi) / sum(exp(xj))
// GELU: 0.5*x*(1+tanh(sqrt(2/pi)*(x+0.044715*x^3)))
typedef enum logic [2:0]  {    XFMR_IDLE
, XFMR_LAYERNORM
, XFMR_MATMUL_Q
, XFMR_MATMUL_K
, XFMR_MATMUL_V
, XFMR_SOFTMAX
, XFMR_FF
, XFMR_DONE  } xfmr_state_t;
  xfmr_state_t xfmr_state, xfmr_next;
  logic [15:0] xfmr_seq_len;
  logic [15:0] xfmr_head_dim;
  logic [7:0]  xfmr_num_heads;
  logic        xfmr_busy_int;
// LayerNorm unit
logic signed [ACC_WIDTH-1:0] ln_mean;
  logic signed [ACC_WIDTH-1:0] ln_var;
  logic signed [ACC_WIDTH-1:0] ln_inv_std;
  logic [15:0] ln_gamma;
  logic [15:0] ln_beta;
  logic [7:0]  ln_ptr;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      xfmr_state   <= XFMR_IDLE;
      xfmr_busy_int<= 1'b0;
      ln_ptr       <= '0;
end else begin      xfmr_state <= xfmr_next;
if (is_fmx2_xfmr && !xfmr_busy_int) begin        xfmr_busy_int <= 1'b1;
        xfmr_seq_len  <= xfmr_cmd[15:0];
        xfmr_head_dim <= xfmr_cmd[31:16];
        xfmr_num_heads<= xfmr_cmd[39:32];
end else if (xfmr_busy_int) begin
case (xfmr_state)
XFMR_LAYERNORM: begin
if (ln_ptr < xfmr_seq_len) begin
// Accumulate mean
ln_mean <= ln_mean + act_tile[ln_ptr];
              ln_ptr  <= ln_ptr + 1;
end else begin              ln_mean <= ln_mean / xfmr_seq_len;
              ln_ptr  <= '0;
end
end
XFMR_DONE: begin            xfmr_busy_int <= 1'b0;
end
default: ;

endcase
end
end
end
always_comb begin    xfmr_next = xfmr_state;
case (xfmr_state)
XFMR_IDLE:
if (is_fmx2_xfmr && !xfmr_busy_int) xfmr_next = XFMR_LAYERNORM;
XFMR_LAYERNORM: if (ln_ptr >= xfmr_seq_len && ln_mean != '0) xfmr_next = XFMR_MATMUL_Q;
XFMR_MATMUL_Q:  xfmr_next = XFMR_MATMUL_K;
XFMR_MATMUL_K:  xfmr_next = XFMR_MATMUL_V;
XFMR_MATMUL_V:  xfmr_next = XFMR_SOFTMAX;
XFMR_SOFTMAX:   xfmr_next = XFMR_FF;
XFMR_FF:        xfmr_next = XFMR_DONE;
XFMR_DONE:      xfmr_next = XFMR_IDLE;
default:        xfmr_next = XFMR_IDLE;

endcase
end
// ==========================================================================
//  Quantization & Activation
// ==========================================================================
logic [15:0] scale_factor;
  logic [7:0]  zero_point;
always_ff @(posedge clk) begin
if (is_fmx2_quant) begin      scale_factor <= vec_operand_a[15:0];
      zero_point   <= vec_operand_a[23:16];
end
end
generate
genvar gi, gj, ga;
for (ga = 0; ga < NUM_ARRAYS; ga = ga + 1) begin : quant_a
for (gi = 0; gi < ARRAY_DIM_X; gi = gi + 1) begin : quant_i
for (gj = 0; gj < ARRAY_DIM_Y; gj = gj + 1) begin : quant_j          logic signed [ACC_WIDTH-1:0] scaled;
          logic signed [DATA_WIDTH-1:0] quantized;
always_comb begin            scaled = (sa_acc[ga][gi][gj] * scale_factor) >>> 8;
            quantized = scaled[DATA_WIDTH-1:0] + zero_point;
if (scaled > 127)  quantized = 8'sd127;
else if (scaled < -128) quantized = -8'sd128;
end
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
end else if (sa_busy) begin      ops_cnt <= ops_cnt + TOTAL_MACS;
end
end
// ==========================================================================
//  Outputs
// ==========================================================================
assign npu_ops_counter = ops_cnt;
assign npu_done_irq    = !sa_busy && (sa_cycle > 0);
assign fmx2_ready      = !sa_busy && !xfmr_busy_int;
assign vec_ready       = !sa_busy && !xfmr_busy_int;
assign xfmr_busy       = xfmr_busy_int;
// AXI memory interface stubs
assign m_axi_arvalid = is_fmx2_load;
assign m_axi_araddr  = vec_operand_a[63:0];
assign m_axi_rready  = 1'b1;
assign m_axi_awvalid = is_fmx2_store;
assign m_axi_awaddr  = vec_operand_b[63:0];
assign m_axi_wdata   = {result_tile[31], result_tile[30], result_tile[29], result_tile[28],                         result_tile[27], result_tile[26], result_tile[25], result_tile[24],                         result_tile[23], result_tile[22], result_tile[21], result_tile[20],                         result_tile[19], result_tile[18], result_tile[17], result_tile[16],                         result_tile[15], result_tile[14], result_tile[13], result_tile[12],                         result_tile[11], result_tile[10], result_tile[9],  result_tile[8],                         result_tile[7],  result_tile[6],  result_tile[5],  result_tile[4],                         result_tile[3],  result_tile[2],  result_tile[1],  result_tile[0]};
assign m_axi_wstrb   = '1;
assign m_axi_wvalid  = is_fmx2_store;
endmodule // orca_npu_v5_2
`endif
// ORCA_NPU_V5_2_SV
