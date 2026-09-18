//============================================================================
// ORCA v5.0 X — Kestrel NPU (Lightweight Edge AI Accelerator)
// Peak Performance: 1 TOPS @ 1GHz (INT8)
// Target Process: 22nm
// Area Estimate: ~0.3 mm2
// Power Estimate: <150mW
//============================================================================
`ifndef ORCA_NPU_V5_SV
`define ORCA_NPU_V5_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_npu_v5 #
( parameter int MAC_UNITS        = 8
, parameter int ACC_WIDTH        = 32
, parameter int WEIGHT_DEPTH     = 1024
// 4KB
, parameter int ACTIVATION_DEPTH = 1024
// 4KB
, parameter int RESULT_DEPTH     = 256
, parameter int DATA_WIDTH       = 8
// INT8 default
, parameter int AXI_ADDR_W       = 64
, parameter int AXI_DATA_W       = 64  )  (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// AXI4-Lite Configuration Interface
// --------------------------------------------------------------------------
, input  logic                    cfg_awvalid
, output logic                    cfg_awready
, input  logic [15:0]             cfg_awaddr
, input  logic                    cfg_wvalid
, output logic                    cfg_wready
, input  logic [63:0]             cfg_wdata
, input  logic [7:0]              cfg_wstrb
, output logic                    cfg_bvalid
, input  logic                    cfg_bready
, output logic [1:0]              cfg_bresp
, input  logic                    cfg_arvalid
, output logic                    cfg_arready
, input  logic [15:0]             cfg_araddr
, output logic                    cfg_rvalid
, input  logic                    cfg_rready
, output logic [63:0]             cfg_rdata
, output logic [1:0]              cfg_rresp
// --------------------------------------------------------------------------
// AXI4 Memory DMA Interface (read channels)
// --------------------------------------------------------------------------
, output logic [AXI_ADDR_W-1:0]   m_axi_araddr
, output logic                    m_axi_arvalid
, input  logic                    m_axi_arready
, input  logic [AXI_DATA_W-1:0]   m_axi_rdata
, input  logic                    m_axi_rvalid
, output logic                    m_axi_rready
, input  logic [1:0]              m_axi_rresp
// --------------------------------------------------------------------------
// AXI4 Memory DMA Interface (write channels)
// --------------------------------------------------------------------------
, output logic [AXI_ADDR_W-1:0]   m_axi_awaddr
, output logic                    m_axi_awvalid
, input  logic                    m_axi_awready
, output logic [AXI_DATA_W-1:0]   m_axi_wdata
, output logic [AXI_DATA_W/8-1:0] m_axi_wstrb
, output logic                    m_axi_wvalid
, input  logic                    m_axi_wready
, input  logic                    m_axi_bvalid
, output logic                    m_axi_bready
, input  logic [1:0]              m_axi_bresp
// --------------------------------------------------------------------------
// Interrupt & Performance
// --------------------------------------------------------------------------
, output logic        npu_irq
, output logic [63:0] npu_ops_counter  );
// ==========================================================================
//  Typedefs & Constants
// ==========================================================================
typedef enum logic [3:0]  {    NPU_IDLE        = 4'd0
, NPU_CFG_LOAD    = 4'd1
, NPU_DMA_WEIGHT  = 4'd2
, NPU_DMA_ACT     = 4'd3
, NPU_COMPUTE     = 4'd4
, NPU_ACTIVATION  = 4'd5
, NPU_DMA_STORE   = 4'd6
, NPU_DONE        = 4'd7  } npu_state_t;
localparam int MAX_DIM = 16'hFFFF;
// ==========================================================================
//  Configuration Registers
// ==========================================================================
logic [15:0] cfg_m, cfg_n, cfg_k;
// GEMM dimensions MxNxK
logic [15:0] cfg_act_rows, cfg_act_cols;
  logic [15:0] cfg_stride;
  logic [2:0]  cfg_act_mode;
// 0:ReLU, 1:ReLU6, 2:Sigmoid(approx), 3:None
logic        cfg_int8_mode;
// 1:INT8, 0:INT16
logic [31:0] cfg_weight_base;
// DDR base address
logic [31:0] cfg_act_base;
  logic [31:0] cfg_result_base;
  logic        cfg_start;
  logic        cfg_start_d;
// Edge detect
logic        cfg_start_pulse;
// ==========================================================================
//  Local SRAMs
// ==========================================================================
logic signed [DATA_WIDTH-1:0]   weight_mem [0:WEIGHT_DEPTH-1];
  logic signed [DATA_WIDTH-1:0]   act_mem    [0:ACTIVATION_DEPTH-1];
  logic signed [ACC_WIDTH-1:0]    acc_mem    [0:MAC_UNITS-1];
  logic signed [DATA_WIDTH-1:0]   result_mem [0:RESULT_DEPTH-1];
// ==========================================================================
//  MAC Array
// ==========================================================================
logic signed [DATA_WIDTH-1:0]   mac_a    [0:MAC_UNITS-1];
  logic signed [DATA_WIDTH-1:0]   mac_w    [0:MAC_UNITS-1];
  logic signed [2*DATA_WIDTH-1:0] mac_prod [0:MAC_UNITS-1];
  logic signed [ACC_WIDTH-1:0]    mac_acc  [0:MAC_UNITS-1];
genvar g;
generate
for (g = 0; g < MAC_UNITS; g++) begin : mac_gen
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin          mac_acc[g] <= '0;
end else if (state == NPU_COMPUTE) begin          mac_prod[g] <= mac_a[g] * mac_w[g];
          mac_acc[g]  <= mac_acc[g] + {{(ACC_WIDTH-2*DATA_WIDTH){mac_prod[g][2*DATA_WIDTH-1]}}, mac_prod[g]};
end else if (state == NPU_IDLE) begin          mac_acc[g] <= '0;
end
end
end
endgenerate
// ==========================================================================
//  Activation Function (ReLU / ReLU6 / Pass-through)
// ==========================================================================
logic signed [DATA_WIDTH-1:0] act_result [0:MAC_UNITS-1];
  logic signed [ACC_WIDTH-1:0] acc_quant;
generate
for (g = 0; g < MAC_UNITS; g++) begin : act_gen
always_comb begin        acc_quant = mac_acc[g];
// Scale and saturate to INT8/INT16
if (acc_quant >  ((1 << (DATA_WIDTH-1)) - 1))          acc_quant =  ((1 << (DATA_WIDTH-1)) - 1);
if (acc_quant < -(1 << (DATA_WIDTH-1)))          acc_quant = -(1 << (DATA_WIDTH-1));
case (cfg_act_mode)
3'd0:  act_result[g] = (acc_quant < 0) ? '0 : acc_quant[DATA_WIDTH-1:0];
 // ReLU
3'd1:
begin // ReLU6 (quantized to 0-6 range for INT8)
if (acc_quant < 0)       act_result[g] = '0;
else if (acc_quant > 6)  act_result[g] = DATA_WIDTH'(6);
else                     act_result[g] = acc_quant[DATA_WIDTH-1:0];
end
default: act_result[g] = acc_quant[DATA_WIDTH-1:0];

endcase
end
end
endgenerate
// ==========================================================================
//  State Machine & Control
// ==========================================================================
npu_state_t state, next_state;
  logic [15:0] row_ptr, col_ptr, k_ptr;
  logic [63:0] ops_cnt;
  logic        compute_done;
// Start pulse detection
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      cfg_start_d <= 1'b0;
end else begin      cfg_start_d <= cfg_start;
end
end
assign cfg_start_pulse = cfg_start && !cfg_start_d;
always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin      state        <= NPU_IDLE;
      row_ptr      <= '0;
      col_ptr      <= '0;
      k_ptr        <= '0;
      ops_cnt      <= '0;
      cfg_start    <= 1'b0;
      npu_irq      <= 1'b0;
      compute_done <= 1'b0;
      cfg_m        <= 16'd32;
      cfg_n        <= 16'd32;
      cfg_k        <= 16'd32;
      cfg_act_mode <= 3'd0;
      cfg_int8_mode <= 1'b1;
end else begin      state <= next_state;
// Configuration load via AXI4-Lite
if (cfg_awvalid && cfg_wvalid) begin
case (cfg_awaddr[15:0])
16'h0000: cfg_m           <= cfg_wdata[15:0];
16'h0004: cfg_n           <= cfg_wdata[15:0];
16'h0008: cfg_k           <= cfg_wdata[15:0];
16'h000C: cfg_weight_base <= cfg_wdata[31:0];
16'h0010: cfg_act_base    <= cfg_wdata[31:0];
16'h0014: cfg_result_base <= cfg_wdata[31:0];
16'h0018: {cfg_act_mode, cfg_int8_mode, cfg_stride} <= cfg_wdata[7:0];
16'h001C: cfg_start       <= cfg_wdata[0];
default: ;

endcase
end
// State-specific operations
case (state)
NPU_COMPUTE: begin
if (k_ptr < cfg_k) begin
// Feed MAC array
for (int i = 0; i < MAC_UNITS; i++) begin
if ((k_ptr + i) < cfg_k) begin                mac_w[i] <= weight_mem[k_ptr + i];
                mac_a[i] <= act_mem[k_ptr + i];
end else begin                mac_w[i] <= '0;
                mac_a[i] <= '0;
end
end            k_ptr   <= k_ptr + MAC_UNITS;
            ops_cnt <= ops_cnt + MAC_UNITS;
end else begin            compute_done <= 1'b1;
// Store results
for (int i = 0; i < MAC_UNITS && i < RESULT_DEPTH; i++) begin              result_mem[i] <= act_result[i];
end
end
end
NPU_DMA_STORE: begin          compute_done <= 1'b0;
end
NPU_DONE: begin          npu_irq   <= 1'b1;
          cfg_start <= 1'b0;
end
NPU_IDLE: begin          npu_irq      <= 1'b0;
          compute_done <= 1'b0;
          row_ptr      <= '0;
          col_ptr      <= '0;
          k_ptr        <= '0;
if (cfg_start_pulse) begin            ops_cnt <= '0;
end
end
default: ;

endcase
end
end
// Next-state logic
always_comb begin    next_state = state;
case (state)
NPU_IDLE:
if (cfg_start_pulse)     next_state = NPU_CFG_LOAD;
NPU_CFG_LOAD:   next_state = NPU_DMA_WEIGHT;
NPU_DMA_WEIGHT: next_state = NPU_DMA_ACT;
NPU_DMA_ACT:    next_state = NPU_COMPUTE;
NPU_COMPUTE:
if (compute_done)        next_state = NPU_ACTIVATION;
NPU_ACTIVATION: next_state = NPU_DMA_STORE;
NPU_DMA_STORE:  next_state = NPU_DONE;
NPU_DONE:       next_state = NPU_IDLE;
default:        next_state = NPU_IDLE;

endcase
end
// ==========================================================================
//  AXI4-Lite Handshaking (simplified)
// ==========================================================================
assign cfg_awready = 1'b1;
assign cfg_wready  = 1'b1;
assign cfg_bvalid  = cfg_awvalid && cfg_wvalid;
assign cfg_bresp   = 2'b00;
assign cfg_arready = 1'b1;
assign cfg_rvalid  = cfg_arvalid;
assign cfg_rresp   = 2'b00;
assign cfg_rdata   = {48'h0, ops_cnt[15:0]};
 // Read ops counter low 16b
// ==========================================================================
//  DMA Interface (stub — connects to AXI crossbar in SoC)
// ==========================================================================
assign m_axi_araddr  = cfg_weight_base;
assign m_axi_arvalid = (state == NPU_DMA_WEIGHT);
assign m_axi_rready  = 1'b1;
assign m_axi_awaddr  = cfg_result_base;
assign m_axi_awvalid = (state == NPU_DMA_STORE);
assign m_axi_wdata   = {result_mem[7], result_mem[6], result_mem[5], result_mem[4],                         result_mem[3], result_mem[2], result_mem[1], result_mem[0]};
assign m_axi_wstrb   = '1;
assign m_axi_wvalid  = (state == NPU_DMA_STORE);
assign m_axi_bready  = 1'b1;
// ==========================================================================
//  Outputs
// ==========================================================================
assign npu_ops_counter = ops_cnt;
endmodule // orca_npu_v5
`endif
// ORCA_NPU_V5_SV
