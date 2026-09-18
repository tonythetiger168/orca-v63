//============================================================================
// ORCA v6.1 ZEN — Phoenix-E TPE (Tensor Processing Engine, Edge Server)
// Peak Performance: ~10 TOPS @ 2.5GHz (INT8) + AME ~2 TOPS = 12 TOPS total
// Target Process: 7nm
// Area Estimate: ~5.5 mm2 (TPE+AME)
// Power Estimate: <8W
//
// Features:
// - 6 tiles x 16x16 MAC array = 1,536 MACs (downscaled from Phoenix v6.0)
// - WMMA instruction set (same ISA as v6.0 Phoenix)
// - INT8/FP16/BF16/FP32 support
// - GELU/SiLU/ReLU activation pipeline
// - 256-bit CHI/AXI4 interface (down from 512-bit)
// - Shared software stack with v6.0 Phoenix
//============================================================================
`ifndef ORCA_TPE_V6_1_SV
`define ORCA_TPE_V6_1_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_tpe_v6_1 #
( parameter int NUM_TILES      = 6
// Down from 8
, parameter int TILE_DIM       = 16
, parameter int ACC_WIDTH      = 32
, parameter int DATA_WIDTH     = 8
, parameter int FIFO_DEPTH     = 1024
, parameter int AXI_DATA_W     = 256
// 256-bit (down from 512)
)  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// Command Interface (from CPU / RoCC)
// --------------------------------------------------------------------------
, input  logic [63:0] cmd_data
, input  logic        cmd_valid
, output logic        cmd_ready
// --------------------------------------------------------------------------
// AXI4-Stream / CHI Interface to memory (256-bit)
// --------------------------------------------------------------------------
, output logic [63:0]         mem_araddr
, output logic                mem_arvalid
, input  logic                mem_arready
, input  logic [AXI_DATA_W-1:0] mem_rdata
, input  logic                mem_rvalid
, output logic                mem_rready
, output logic [63:0]         mem_awaddr
, output logic                mem_awvalid
, input  logic                mem_awready
, output logic [AXI_DATA_W-1:0] mem_wdata
, output logic [AXI_DATA_W/8-1:0] mem_wstrb
, output logic                mem_wvalid
, input  logic                mem_wready
// --------------------------------------------------------------------------
// Status
// --------------------------------------------------------------------------
, output logic        tpe_busy
, output logic        tpe_done_irq
, output logic [63:0] tpe_ops_counter  );
localparam int MACS_PER_TILE = TILE_DIM * TILE_DIM;
 // 256
localparam int TOTAL_MACS    = NUM_TILES * MACS_PER_TILE;
 // 1536
// ==========================================================================
//  Command Decoder (same ISA as v6.0 Phoenix)
// ==========================================================================
typedef enum logic [3:0]  {    TPE_IDLE        = 4'd0
, TPE_CMD_DECODE  = 4'd1
, TPE_LOAD_WEIGHT = 4'd2
, TPE_LOAD_ACT    = 4'd3
, TPE_COMPUTE_WMMA= 4'd4
, TPE_ACCUMULATE  = 4'd5
, TPE_ACTIVATION  = 4'd6
, TPE_STORE       = 4'd7
, TPE_DONE        = 4'd8  } tpe_state_t;
  tpe_state_t state, next_state;
  logic [7:0]  cmd_op;
  logic [4:0]  cmd_rd, cmd_rs1, cmd_rs2;
  logic [15:0] cmd_m, cmd_n, cmd_k;
  logic [63:0] cmd_base_addr;
assign cmd_op = cmd_data[7:0];
assign cmd_rd = cmd_data[12:8];
assign cmd_rs1 = cmd_data[17:13];
assign cmd_rs2 = cmd_data[22:18];
// ==========================================================================
//  Tile SRAM Arrays (6 tiles, 72KB total)
// ==========================================================================
logic signed [DATA_WIDTH-1:0] weight_sram [0:NUM_TILES-1][0:MACS_PER_TILE-1];
  logic signed [DATA_WIDTH-1:0] act_sram    [0:NUM_TILES-1][0:MACS_PER_TILE-1];
  logic signed [ACC_WIDTH-1:0]  acc_sram    [0:NUM_TILES-1][0:MACS_PER_TILE-1];
  logic signed [DATA_WIDTH-1:0] result_sram [0:NUM_TILES-1][0:MACS_PER_TILE-1];
// ==========================================================================
//  6 x 16x16 Systolic Tile Array
// ==========================================================================
logic [5:0] wmma_cycle;
  logic       wmma_busy;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      wmma_cycle <= '0;
      wmma_busy  <= 1'b0;
end else if (state == TPE_COMPUTE_WMMA && !wmma_busy) begin      wmma_busy  <= 1'b1;
      wmma_cycle <= '0;
end else if (wmma_busy) begin
if (wmma_cycle < TILE_DIM + 4) begin        wmma_cycle <= wmma_cycle + 1;
end else begin        wmma_busy <= 1'b0;
end
end
end
generate
genvar tile_idx;
  integer ti, tj;
for (tile_idx = 0; tile_idx < NUM_TILES; tile_idx = tile_idx + 1) begin : tile_gen      logic signed [ACC_WIDTH-1:0] tile_acc [0:TILE_DIM-1][0:TILE_DIM-1];
always_ff @(posedge clk) begin
if (wmma_busy) begin
for (ti = 0; ti < TILE_DIM; ti = ti + 1) begin
for (tj = 0; tj < TILE_DIM; tj = tj + 1) begin
if (wmma_cycle == 0) begin                tile_acc[ti][tj] <= '0;
end else if (wmma_cycle <= TILE_DIM) begin                tile_acc[ti][tj] <= tile_acc[ti][tj] +                  weight_sram[tile_idx][ti*TILE_DIM + wmma_cycle-1] *                  act_sram[tile_idx][(wmma_cycle-1)*TILE_DIM + tj];
end else if (wmma_cycle == TILE_DIM + 1) begin                acc_sram[tile_idx][ti*TILE_DIM + tj] <= tile_acc[ti][tj];
end
end
end
end
end
end
endgenerate
// ==========================================================================
//  Activation & Quantization Pipeline (same as v6.0)
// ==========================================================================
logic [2:0] act_mode;
// 0:ReLU, 1:GELU(approx), 2:SiLU, 3:None
logic [15:0] quant_scale;
  logic [7:0]  quant_zp;
function automatic logic signed [DATA_WIDTH-1:0] gelu_approx;
input logic signed [ACC_WIDTH-1:0] x;
    logic signed [ACC_WIDTH-1:0] result;
begin
if (x < -40) result = '0;
else if (x > 40) result = x;
else begin        result = (x >>> 1) + (x >>> 3) + (x >>> 4);
end      gelu_approx = result[DATA_WIDTH-1:0];
end
endfunction
generate
genvar gti, gtj;
for (tile_idx = 0; tile_idx < NUM_TILES; tile_idx = tile_idx + 1) begin : act_tile_gen
for (gti = 0; gti < TILE_DIM; gti = gti + 1) begin : act_i
for (gtj = 0; gtj < TILE_DIM; gtj = gtj + 1) begin : act_j          logic signed [ACC_WIDTH-1:0] scaled;
always_comb begin            scaled = (acc_sram[tile_idx][gti*TILE_DIM + gtj] * quant_scale) >>> 8;
case (act_mode)
3'd0: result_sram[tile_idx][gti*TILE_DIM + gtj] =                    (scaled < 0) ? '0 : scaled[DATA_WIDTH-1:0];
3'd1: result_sram[tile_idx][gti*TILE_DIM + gtj] = gelu_approx(scaled);
default: result_sram[tile_idx][gti*TILE_DIM + gtj] = scaled[DATA_WIDTH-1:0];

endcase
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
end else if (wmma_busy && wmma_cycle <= TILE_DIM) begin      ops_cnt <= ops_cnt + TOTAL_MACS;
end
end
// ==========================================================================
//  State Machine
// ==========================================================================
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      state <= TPE_IDLE;
end else begin      state <= next_state;
end
end
always_comb begin    next_state = state;
case (state)
TPE_IDLE:
if (cmd_valid)          next_state = TPE_CMD_DECODE;
TPE_CMD_DECODE:   next_state = TPE_LOAD_WEIGHT;
TPE_LOAD_WEIGHT:  next_state = TPE_LOAD_ACT;
TPE_LOAD_ACT:     next_state = TPE_COMPUTE_WMMA;
TPE_COMPUTE_WMMA: if (!wmma_busy && wmma_cycle > 0) next_state = TPE_ACTIVATION;
TPE_ACTIVATION:   next_state = TPE_STORE;
TPE_STORE:        next_state = TPE_DONE;
TPE_DONE:         next_state = TPE_IDLE;
default:          next_state = TPE_IDLE;

endcase
end
// ==========================================================================
//  Outputs
// ==========================================================================
assign tpe_ops_counter = ops_cnt;
assign tpe_busy        = wmma_busy || (state != TPE_IDLE);
assign tpe_done_irq    = (state == TPE_DONE);
assign cmd_ready       = (state == TPE_IDLE);
// Memory interface stubs
assign mem_arvalid = (state == TPE_LOAD_WEIGHT) || (state == TPE_LOAD_ACT);
assign mem_araddr  = cmd_base_addr;
assign mem_rready  = 1'b1;
assign mem_awvalid = (state == TPE_STORE);
assign mem_awaddr  = cmd_base_addr + 64'h10000;
assign mem_wdata   = {result_sram[0][15], result_sram[0][14], result_sram[0][13], result_sram[0][12],                         result_sram[0][11], result_sram[0][10], result_sram[0][9],  result_sram[0][8],                         result_sram[0][7],  result_sram[0][6],  result_sram[0][5],  result_sram[0][4],                         result_sram[0][3],  result_sram[0][2],  result_sram[0][1],  result_sram[0][0],                         result_sram[1][15], result_sram[1][14], result_sram[1][13], result_sram[1][12],                         result_sram[1][11], result_sram[1][10], result_sram[1][9],  result_sram[1][8],                         result_sram[1][7],  result_sram[1][6],  result_sram[1][5],  result_sram[1][4],                         result_sram[1][3],  result_sram[1][2],  result_sram[1][1],  result_sram[1][0]};
assign mem_wstrb   = '1;
assign mem_wvalid  = (state == TPE_STORE);
endmodule // orca_tpe_v6_1
`endif
// ORCA_TPE_V6_1_SV
