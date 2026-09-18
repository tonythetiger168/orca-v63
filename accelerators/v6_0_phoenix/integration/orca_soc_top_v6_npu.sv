//============================================================================
// ORCA v6.0 ZEN SoC — Phoenix AI Subsystem Integration
// Connects TPE + AME to CHI mesh NoC and CPU CSR interface
//============================================================================
`ifndef ORCA_SOC_TOP_V6_NPU_SV
`define ORCA_SOC_TOP_V6_NPU_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_soc_top_v6_npu (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// Command Interface (from Core 0 CSR)
// --------------------------------------------------------------------------
, input  logic [63:0] phoenix_cmd
, input  logic        phoenix_cmd_valid
, output logic        phoenix_cmd_ready
// --------------------------------------------------------------------------
// CHI / AXI4-Stream to Mesh NoC (512-bit)
// --------------------------------------------------------------------------
, output logic [63:0]         noc_araddr
, output logic                noc_arvalid
, input  logic                noc_arready
, input  logic [511:0]        noc_rdata
, input  logic                noc_rvalid
, output logic                noc_rready
, output logic [63:0]         noc_awaddr
, output logic                noc_awvalid
, input  logic                noc_awready
, output logic [511:0]        noc_wdata
, output logic [63:0]         noc_wstrb
, output logic                noc_wvalid
, input  logic                noc_wready
// --------------------------------------------------------------------------
// Interrupts to PLIC
// --------------------------------------------------------------------------
, output logic        tpe_irq
, output logic        ame_irq
// --------------------------------------------------------------------------
// Performance counters
// --------------------------------------------------------------------------
, output logic [63:0] tpe_ops_counter
, output logic [63:0] ame_ops_counter  );
// --------------------------------------------------------------------------
//  TPE Instance
// --------------------------------------------------------------------------
orca_tpe_v6 #    ( .NUM_TILES(8)
, .TILE_DIM(16)
, .ACC_WIDTH(32)
, .DATA_WIDTH(8)
, .FIFO_DEPTH(1024)
, .AXI_DATA_W(512)    ) u_tpe (
.clk            (clk)
, .rst_n          (rst_n)
, .cmd_data       (phoenix_cmd)
, .cmd_valid      (phoenix_cmd_valid && (phoenix_cmd[7:0] < 8'h10))
, .cmd_ready      (phoenix_cmd_ready)
, .mem_araddr     (noc_araddr)
, .mem_arvalid    (noc_arvalid)
, .mem_arready    (noc_arready)
, .mem_rdata      (noc_rdata)
, .mem_rvalid     (noc_rvalid)
, .mem_rready     (noc_rready)
, .mem_awaddr     (noc_awaddr)
, .mem_awvalid    (noc_awvalid)
, .mem_awready    (noc_awready)
, .mem_wdata      (noc_wdata)
, .mem_wstrb      (noc_wstrb)
, .mem_wvalid     (noc_wvalid)
, .mem_wready     (noc_wready)
, .tpe_busy       ()
, .tpe_done_irq   (tpe_irq)
, .tpe_ops_counter(tpe_ops_counter)  );
// --------------------------------------------------------------------------
//  AME Instance
// --------------------------------------------------------------------------
logic [31:0] csr_row_ptr [0:127];
  logic [15:0] csr_col_idx [0:1023];
  logic signed [7:0] csr_values [0:1023];
  logic signed [7:0] dense_vec [0:255];
  orca_ame_v6 #    ( .NUM_BLOCKS(16)
, .BLOCK_DIM(8)
, .SPARSE_RATIO(2)
, .ACC_WIDTH(32)
, .IDX_WIDTH(16)    ) u_ame (
.clk              (clk)
, .rst_n            (rst_n)
, .sparse_cmd       (phoenix_cmd)
, .sparse_cmd_valid (phoenix_cmd_valid && (phoenix_cmd[7:0] >= 8'h10))
, .sparse_cmd_ready ()
, .csr_row_ptr      (csr_row_ptr)
, .csr_col_idx      (csr_col_idx)
, .csr_values       (csr_values)
, .dense_vec        (dense_vec)
, .vec_valid        (1'b0)
, .sparse_result    ()
, .result_valid     ()
, .ame_ops_counter  (ame_ops_counter)  );
// AME interrupt (simplified)
assign ame_irq = 1'b0;
endmodule
`endif
