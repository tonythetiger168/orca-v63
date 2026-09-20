//============================================================================
// ORCA v6.2 ZEN SoC — Phoenix+ Multi-Chip AI Subsystem Integration
// Dual-die configuration via UCIe/Chiplet interconnect
// Total: 32 TOPS INT8 (16 TOPS per die)
// Die 0: Master (scheduling + TPE/AME)
// Die 1: Slave (compute-only TPE/AME)
// Coherent global address space across both dies
//============================================================================
`ifndef ORCA_SOC_TOP_V6_2_NPU_SV
`define ORCA_SOC_TOP_V6_2_NPU_SV
`include "orca_params.sv"
`include "orca_pkg.sv"
module orca_soc_top_v6_2_npu (
input  logic        clk
, input  logic        rst_n
// --------------------------------------------------------------------------
// Command Interface (from Core 0 CSR, master die only)
// --------------------------------------------------------------------------
, input  logic [63:0] phoenix_cmd
, input  logic        phoenix_cmd_valid
, output logic        phoenix_cmd_ready
// --------------------------------------------------------------------------
// CHI / AXI4-Stream to Crossbar (512-bit, per-die)
// --------------------------------------------------------------------------
, output logic [63:0]         die0_araddr
, output logic                die0_arvalid
, input  logic                die0_arready
, input  logic [511:0]        die0_rdata
, input  logic                die0_rvalid
, output logic                die0_rready
, output logic [63:0]         die0_awaddr
, output logic                die0_awvalid
, input  logic                die0_awready
, output logic [511:0]        die0_wdata
, output logic [63:0]         die0_wstrb
, output logic                die0_wvalid
, input  logic                die0_wready
, output logic [63:0]         die1_araddr
, output logic                die1_arvalid
, input  logic                die1_arready
, input  logic [511:0]        die1_rdata
, input  logic                die1_rvalid
, output logic                die1_rready
, output logic [63:0]         die1_awaddr
, output logic                die1_awvalid
, input  logic                die1_awready
, output logic [511:0]        die1_wdata
, output logic [63:0]         die1_wstrb
, output logic                die1_wvalid
, input  logic                die1_wready
// --------------------------------------------------------------------------
// UCIe Die-to-Die Interface (between dies)
// --------------------------------------------------------------------------
, output logic [255:0]        d2d_tx_data
, output logic                d2d_tx_valid
, input  logic                d2d_tx_ready
, input  logic [255:0]        d2d_rx_data
, input  logic                d2d_rx_valid
, output logic                d2d_rx_ready
// --------------------------------------------------------------------------
// Interrupts to PLIC
// --------------------------------------------------------------------------
, output logic        tpe0_irq
, output logic        ame0_irq
, output logic        tpe1_irq
, output logic        ame1_irq
// --------------------------------------------------------------------------
// Performance counters
// --------------------------------------------------------------------------
, output logic [63:0] tpe0_ops_counter
, output logic [63:0] ame0_ops_counter
, output logic [63:0] tpe1_ops_counter
, output logic [63:0] ame1_ops_counter
, output logic        d2d_link_up  );
// --------------------------------------------------------------------------
//  Die 0 — Master (TPE v6.2 + AME v6.2, DIE_ID=0)
// --------------------------------------------------------------------------
logic [63:0] die0_cmd;
  logic        die0_cmd_valid;
  logic        die0_cmd_ready;
assign die0_cmd       = phoenix_cmd;
assign die0_cmd_valid = phoenix_cmd_valid && (phoenix_cmd[40] == 1'b0);
  orca_tpe_v6_2 #    ( .NUM_TILES(8)
, .TILE_DIM(16)
, .ACC_WIDTH(32)
, .DATA_WIDTH(8)
, .FIFO_DEPTH(1024)
, .AXI_DATA_W(512)
, .D2D_DATA_W(256)
, .DIE_ID(0)    ) u_tpe_die0 (
.clk            (clk)
, .rst_n          (rst_n)
, .cmd_data       (die0_cmd)
, .cmd_valid      (die0_cmd_valid)
, .cmd_ready      (die0_cmd_ready)
, .mem_araddr     (die0_araddr)
, .mem_arvalid    (die0_arvalid)
, .mem_arready    (die0_arready)
, .mem_rdata      (die0_rdata)
, .mem_rvalid     (die0_rvalid)
, .mem_rready     (die0_rready)
, .mem_awaddr     (die0_awaddr)
, .mem_awvalid    (die0_awvalid)
, .mem_awready    (die0_awready)
, .mem_wdata      (die0_wdata)
, .mem_wstrb      (die0_wstrb)
, .mem_wvalid     (die0_wvalid)
, .mem_wready     (die0_wready)
, .d2d_tx_data    (d2d_tx_data)
, .d2d_tx_valid   (d2d_tx_valid)
, .d2d_tx_ready   (d2d_tx_ready)
, .d2d_rx_data    (d2d_rx_data)
, .d2d_rx_valid   (d2d_rx_valid)
, .d2d_rx_ready   (d2d_rx_ready)
, .tpe_busy       ()
, .tpe_done_irq   (tpe0_irq)
, .tpe_ops_counter(tpe0_ops_counter)
, .d2d_link_up    (d2d_link_up)  );
  orca_ame_v6_2 #    ( .NUM_BLOCKS(16)
, .BLOCK_DIM(8)
, .SPARSE_RATIO(2)
, .ACC_WIDTH(32)
, .IDX_WIDTH(16)
, .D2D_DATA_W(256)
, .DIE_ID(0)    ) u_ame_die0 (
.clk              (clk)
, .rst_n            (rst_n)
, .sparse_cmd       (die0_cmd)
, .sparse_cmd_valid (die0_cmd_valid)
, .sparse_cmd_ready ()
, .csr_row_ptr      ()
, .csr_col_idx      ()
, .csr_values       ()
, .dense_vec        ()
, .vec_valid        (1'b0)
, .sparse_result    ()
, .result_valid     ()
, .d2d_tx_data      ()
, .d2d_tx_valid     ()
, .d2d_tx_ready     (1'b1)
, .d2d_rx_data      (256'h0)
, .d2d_rx_valid     (1'b0)
, .d2d_rx_ready     ()
, .ame_ops_counter  (ame0_ops_counter)
, .d2d_link_up      ()  );
// --------------------------------------------------------------------------
//  Die 1 — Slave (TPE v6.2 + AME v6.2, DIE_ID=1)
// --------------------------------------------------------------------------
logic [63:0] die1_cmd;
  logic        die1_cmd_valid;
assign die1_cmd       = phoenix_cmd;
assign die1_cmd_valid = phoenix_cmd_valid && (phoenix_cmd[40] == 1'b1);
  orca_tpe_v6_2 #    ( .NUM_TILES(8)
, .TILE_DIM(16)
, .ACC_WIDTH(32)
, .DATA_WIDTH(8)
, .FIFO_DEPTH(1024)
, .AXI_DATA_W(512)
, .D2D_DATA_W(256)
, .DIE_ID(1)    ) u_tpe_die1 (
.clk            (clk)
, .rst_n          (rst_n)
, .cmd_data       (die1_cmd)
, .cmd_valid      (die1_cmd_valid)
, .cmd_ready      ()
, .mem_araddr     (die1_araddr)
, .mem_arvalid    (die1_arvalid)
, .mem_arready    (die1_arready)
, .mem_rdata      (die1_rdata)
, .mem_rvalid     (die1_rvalid)
, .mem_rready     (die1_rready)
, .mem_awaddr     (die1_awaddr)
, .mem_awvalid    (die1_awvalid)
, .mem_awready    (die1_awready)
, .mem_wdata      (die1_wdata)
, .mem_wstrb      (die1_wstrb)
, .mem_wvalid     (die1_wvalid)
, .mem_wready     (die1_wready)
, .d2d_tx_data    ()
, .d2d_tx_valid   ()
, .d2d_tx_ready   (1'b1)
, .d2d_rx_data    (256'h0)
, .d2d_rx_valid   (1'b0)
, .d2d_rx_ready   ()
, .tpe_busy       ()
, .tpe_done_irq   (tpe1_irq)
, .tpe_ops_counter(tpe1_ops_counter)
, .d2d_link_up    ()  );
  orca_ame_v6_2 #    ( .NUM_BLOCKS(16)
, .BLOCK_DIM(8)
, .SPARSE_RATIO(2)
, .ACC_WIDTH(32)
, .IDX_WIDTH(16)
, .D2D_DATA_W(256)
, .DIE_ID(1)    ) u_ame_die1 (
.clk              (clk)
, .rst_n            (rst_n)
, .sparse_cmd       (die1_cmd)
, .sparse_cmd_valid (die1_cmd_valid)
, .sparse_cmd_ready ()
, .csr_row_ptr      ()
, .csr_col_idx      ()
, .csr_values       ()
, .dense_vec        ()
, .vec_valid        (1'b0)
, .sparse_result    ()
, .result_valid     ()
, .d2d_tx_data      ()
, .d2d_tx_valid     ()
, .d2d_tx_ready     (1'b1)
, .d2d_rx_data      (256'h0)
, .d2d_rx_valid     (1'b0)
, .d2d_rx_ready     ()
, .ame_ops_counter  (ame1_ops_counter)
, .d2d_link_up      ()  );
assign phoenix_cmd_ready = die0_cmd_ready;
endmodule
`endif
