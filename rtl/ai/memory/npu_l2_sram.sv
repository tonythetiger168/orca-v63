// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// AI L2 SRAM: AI_L2_SIZE_MB, 16 bank, 1R1W, ECC scrub stub
module npu_l2_sram
  import orca_pkg::*; (
  input  logic clk, rst_n,
  input  logic [31:0] rd_addr,
  input  logic        rd_req,
  output logic [511:0] rd_data,
  input  logic [31:0] wr_addr,
  input  logic        wr_req,
  input  logic [511:0] wr_data,
  input  logic        scrub_en,   /*verilator coverage_off*/ // ecc_err tie-off stub
  output logic        ecc_err   /*verilator coverage_on*/
);
  import orca_pkg::*;
  localparam int BANKS = 16;
  // Behavioral model: depth capped for simulation speed
  localparam int REAL_DEPTH = AI_L2_SIZE_MB * 1024 * 1024 / (BANKS * 64);
  localparam int DEPTH = (REAL_DEPTH > 1024) ? 1024 : REAL_DEPTH;
  logic [511:0] mem [BANKS][DEPTH];
  logic [31:0] scrub_ptr;
  wire [3:0] rbank = rd_addr[9:6];
  wire [3:0] wbank = wr_addr[9:6];
  assign rd_data = mem[rbank][rd_addr[31:10] % DEPTH];
  assign ecc_err = 1'b0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scrub_ptr <= '0;
      for (int b = 0; b < BANKS; b++)
        for (int d = 0; d < DEPTH; d++) mem[b][d] <= '0;
    end else begin
      if (wr_req) mem[wbank][wr_addr[31:10] % DEPTH] <= wr_data;
      if (scrub_en) scrub_ptr <= scrub_ptr + 64;
    end
  end
endmodule : npu_l2_sram
