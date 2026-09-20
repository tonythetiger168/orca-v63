# ORCA v6.3.2 技術工作完成報告 (2026-09-13)

## 交付摘要
- RTL 模組: 13/49 → 49/49（含 orca_pkg 基礎套件、SoC 頂層）
- 驗證: Verilator 5.006 lint 4 頂層 0 錯誤（cpu_core/cpu_tile/ai_tile/soc 全晶片連通性）
- 仿真: 3/3 smoke TB PASS（Verilator --binary --timing）
  - tb_top: "TB PASS: 7 L2 fetches"
  - orca_noc_tb: "TB PASS: flit received"
  - ai_tile_smoke_tb: "TB PASS: AIX GEMM completed in 3 cycles"
- 圖表: 14 張（含 12 管線圖、13 完成度、14 覆蓋計畫）
- 修復總計 30+ 項（語法/型別/端口、宏化、Icarus/codegen 相容、GSCU irq 功能 bug）

## 工具鏈
Verilator 5.006 + Icarus Verilog 12.0（apt 鏡像切換 deb.debian.org 後安裝）

## v6.3.3 路線圖
1. PRF 讀埠供給 EXU 操作數；LSU×4 接入排程
2. ROB 精確 flush + freelist retire 完整回接
3. NoC mesh router 埠位對接（flit_t adapter）
4. npu_hbm3_ctrl / npu_attn_engine 接入 ai_tile
5. UVM directed sequences + 覆蓋率收斂
6. SoC 全參數 lint（需 >4GB 記憶體或 Verilator --hierarchical）
