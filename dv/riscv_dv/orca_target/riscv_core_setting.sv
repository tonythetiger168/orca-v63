// SPDX-License-Identifier: Apache-2.0
// ORCA v6.3 - riscv-dv 客製 target (Google riscv-dv)
// 用法: 將此目錄加入 riscv-dv target 路徑, --target=orca
`ifndef ORCA_CORE_SETTING
`define ORCA_CORE_SETTING
// ZEN++ RV64GCV, SMT-4
parameter int XLEN = 64;
parameter satp_mode_t SATP_MODE = SATP_SV48;
parameter bit SUPPORT_PMP = 1'b1;
parameter bit SUPPORT_SMT = 1'b1;      // ZEN++ SMT-4
// 支援擴展
parameter bit RV32I  = 0; parameter bit RV64I = 1;
parameter bit RV32M  = 1; parameter bit RV64M = 1;
parameter bit RV32A  = 1; parameter bit RV64A = 1;
parameter bit RV32F  = 1; parameter bit RV64F = 1;
parameter bit RV32D  = 1; parameter bit RV64D = 1;
parameter bit RV32C  = 1; parameter bit RV64C = 1;
parameter bit RVV    = 1;              // RVV1.0 VLEN=512
parameter bit RVC    = 1;
parameter bit RVB    = 0; parameter bit RVZICOND = 1;
// 實作
parameter int NUM_HARTS = 1;
parameter int PHYSICAL_ADDR_WIDTH = 64;
// 不支援 (發生即為 unsupported)
parameter bit IMPLEMENTED_EC = 1; parameter bit SUPPORT_SBPI = 0;
`endif
