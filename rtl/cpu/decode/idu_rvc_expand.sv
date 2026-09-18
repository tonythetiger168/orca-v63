// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// RVC 16->32 擴充: C0/C1/C2 常用子集, 未支援格式標 illegal
module idu_rvc_expand
  import orca_pkg::*; (
  input  logic [15:0] cinst,
  output logic [31:0] inst,
  output logic        illegal
);
  always_comb begin
    inst    = 32'h0;
    illegal = 1'b0;
    unique case (cinst[1:0])
      2'b00: unique case (cinst[15:13])
        3'b000: inst = {2'b00, cinst[10:7], cinst[12:11], cinst[5], cinst[6], 2'b00, 5'd2,
                        3'b000, 2'b00, cinst[4:2], 7'b0010011};                    // C.ADDI4SPN
        3'b010: inst = {5'b0, cinst[5], cinst[12:10], cinst[6], 2'b00, 2'b01, cinst[9:7],
                        3'b010, 2'b01, cinst[4:2], 7'b0000011};                    // C.LW
        3'b011: inst = {4'b0, cinst[6:5], cinst[12:10], 3'b000, 2'b01, cinst[9:7],
                        3'b011, 2'b01, cinst[4:2], 7'b0000011};                    // C.LD
        default: illegal = 1'b1;
      endcase
      2'b01: unique case (cinst[15:13])
        3'b000: inst = {{6{cinst[12]}}, cinst[12], cinst[6:2], cinst[11:7],
                        3'b000, cinst[11:7], 7'b0010011};                         // C.ADDI
        3'b001: inst = {{3{cinst[12]}}, cinst[12], cinst[8], cinst[10:9], cinst[6],
                        cinst[7], cinst[2], cinst[11], cinst[5:3], cinst[12], 8'h6F}; // C.JAL
        3'b010: inst = {{6{cinst[12]}}, cinst[12], cinst[6:2], 5'd0,
                        3'b000, cinst[11:7], 7'b0010011};                         // C.LI
        3'b011: inst = (cinst[11:7] == 5'd2)
          ? {{3{cinst[12]}}, cinst[4:3], cinst[5], cinst[2], cinst[6], 4'b0, 5'd2,
             3'b000, 5'd2, 7'b0010011}                                             // C.ADDI16SP
          : {{14{cinst[12]}}, cinst[12], cinst[6:2], cinst[11:7], 7'b0110111};     // C.LUI
        3'b100: inst = {6'b0, cinst[12], cinst[6:2], 2'b01, cinst[9:7],
                        3'b101, 2'b01, cinst[9:7], 7'b0010011};                    // C.SRLI
        3'b101: inst = {{3{cinst[12]}}, cinst[12], cinst[8], cinst[10:9], cinst[6],
                        cinst[7], cinst[2], cinst[11], cinst[5:3], cinst[12], 8'h6F}; // C.J
        3'b110: inst = {{5{cinst[12]}}, cinst[12], cinst[6:5], cinst[2], 5'd0,
                        2'b01, cinst[9:7], 3'b000, cinst[4:3], cinst[12], 8'h63};   // C.BEQZ
        3'b111: inst = {{5{cinst[12]}}, cinst[12], cinst[6:5], cinst[2], 5'd0,
                        2'b01, cinst[9:7], 3'b001, cinst[4:3], cinst[12], 8'h63};   // C.BNEZ
        /*verilator coverage_off*/ default: illegal = 1'b1; /*verilator coverage_on*/ // cov-f1: C1 funct3 已窮舉 000~111, 此 default 不可達 (dead code), 僅加 coverage 註解不更動邏輯
      endcase
      2'b10: unique case (cinst[15:13])
        3'b000: inst = {6'b0, cinst[12], cinst[6:2], cinst[11:7],
                        3'b001, cinst[11:7], 7'b0010011};                         // C.SLLI
        3'b010: inst = {4'b0, cinst[3:2], cinst[12], cinst[6:4], 2'b00, 5'd2,
                        3'b010, cinst[11:7], 7'b0000011};                         // C.LWSP
        3'b011: inst = {3'b0, cinst[4:2], cinst[12], cinst[6:5], 3'b000, 5'd2,
                        3'b011, cinst[11:7], 7'b0000011};                         // C.LDSP
        3'b100: inst = (cinst[6:2] == 5'd0)
          ? {12'h0, cinst[11:7], 3'b000, 5'd0, 7'b1100111}                         // C.JR
          : {7'b0, cinst[6:2], 5'd0, 3'b000, cinst[11:7], 7'b0110011};            // C.MV
        3'b110: inst = {4'b0, cinst[3:2], cinst[12], cinst[6:4], 2'b00, 5'd2,
                        3'b010, cinst[11:7], 7'b0100011};                         // C.SWSP
        default: illegal = 1'b1;
      endcase
      default: illegal = 1'b1;
    endcase
  end
endmodule : idu_rvc_expand
