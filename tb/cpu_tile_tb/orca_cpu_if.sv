//=============================================================================
// ORCA v6.3 UVM CPU Tile Interface
// File: tb/cpu_tile_tb/orca_cpu_if.sv
// Description: Driver/monitor 共用的 CPU tile 針腳介面
//   v6.3.3: 新增 flush / LSU lane / PRF 寫入觀察點, 供 monitor covergroup
//           (opcode 類別 / flush 事件 / LSU lane 使用) 取樣
//=============================================================================

`ifndef ORCA_CPU_IF_SV
`define ORCA_CPU_IF_SV

`include "orca_pkg.sv"

interface orca_cpu_if (input logic clk);
  import orca_pkg::*;

  // ---------------------------------------------------------------------------
  // Driver -> DUT: fetch / decode 注入
  // ---------------------------------------------------------------------------
  logic        fetch_req_valid;
  logic        fetch_ready;
  logic [63:0] fetch_pc;
  tid_t        fetch_tid;

  logic [31:0] decode_instr;
  logic        decode_valid;
  tid_t        decode_tid;
  logic [63:0] decode_rs1_data;
  logic [63:0] decode_rs2_data;

  // ---------------------------------------------------------------------------
  // Monitor <- DUT: retire 觀察 (每 retire port 一組)
  // ---------------------------------------------------------------------------
  logic [RETIRE_WIDTH-1:0]  retire_valid;
  logic [63:0]              retire_pc     [RETIRE_WIDTH];
  tid_t                     retire_tid    [RETIRE_WIDTH];
  logic [63:0]              retire_result [RETIRE_WIDTH];
  logic [RETIRE_WIDTH-1:0]  retire_exception;
  exception_t               retire_exc_code [RETIRE_WIDTH];
  logic [31:0]              retire_instr  [RETIRE_WIDTH];

  // ---------------------------------------------------------------------------
  // v6.3.3: flush / LSU lane / PRF 寫入觀察點 (coverage 用)
  // ---------------------------------------------------------------------------
  logic                     flush_valid;       // cmt_rob flush_pipeline
  logic [63:0]              flush_pc;          // flush redirect pc
  logic [NUM_LD_PIPE-1:0]   lsu_lane_valid;    // isu_mem 4 條 lane issue valid
  logic [11:0]              prf_wvalid;        // PRF 12 寫埠 valid

  // ---------------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------------
  modport drv (
    input  clk, fetch_ready,
    output fetch_req_valid, fetch_pc, fetch_tid,
           decode_instr, decode_valid, decode_tid,
           decode_rs1_data, decode_rs2_data
  );

  modport mon (
    input clk, retire_valid, retire_pc, retire_tid, retire_result,
          retire_exception, retire_exc_code, retire_instr,
          flush_valid, flush_pc, lsu_lane_valid, prf_wvalid
  );

endinterface : orca_cpu_if

`endif // ORCA_CPU_IF_SV
