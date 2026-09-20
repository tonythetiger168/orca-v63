# ORCA v6.3 開源 DV 生態 (支援全系產品: Kestrel → Garuda)

本目錄整合业界標準開源 DV 流程，驗證 ZEN++ RISC-V CPU 全系（邊緣到雲端同一 ISA）。

## 流程總覽

```
riscv-dv (Google 隨機指令產生器, --target=orca)
   │  .S / .hex (RV64IM random programs)
   ▼
Spike (riscv-isa-sim) 黃金參考 ──► golden trace (log-commits)
   │                                    │
   ▼                                    │ async-lockstep 比對
ORCA ZEN++ RTL (Verilator) ◄───────────┘ (每條 in-order retire: PC/rd/result)
   │
   ▼
Core-V-Verif 式環境 (testlist, Makefile, 覆蓋率) + 覆蓋率合併
```

## 元件

| 元件 | 路徑 | 說明 |
|---|---|---|
| 黃金參考 ISS | `dv/golden/orca_iss.sv` | 內嵌 RV64IM ISS（鏡像架構暫存器）。離線 smoke 無需 Spike；生產經 DPI 換 Spike/ImperasDV（介面相同） |
| async-lockstep TB | `dv/lockstep/orca_lockstep_tb.sv` | 每條 in-order retire 與 ISS 比對 PC/rd/result，`0 mismatch` 為 PASS |
| riscv-dv target | `dv/riscv_dv/orca_target/` | 客製 ORCA target（RV64GCV, SMT-4, SV48） |
| 離線 lockstep | `dv/scripts/run_lockstep.sh` | 無 Spike 依賴的快速驗證 |
| 完整 riscv-dv 流程 | `dv/scripts/run_riscv_dv.sh` | riscv-dv→Spike→RTL→比對→覆蓋率 |

## async-lockstep 方法

- **錨點**：`cmt_rob.retire_entry[0]`（in-order 提交頭）。ROB 依序退休，ISS 以相同順序執行。
- **比對**：每條退休指令，ISS 讀自身鏡像 `x[]` 計算期望值，與 `retire_entry[0].result` 比對（`rd=x0`/load/store/branch 略過 rd 值）。
- **async**：RTL（Verilator 週期精確）與 golden（Spike/ISS 指令精確）不同步推進，僅在退休點對齊比對——容忍微架構延遲差異。
- **0 mismatch** 即架構正確（架構暫存器/記憶體語義與 golden 一致）。

## 生產：Spike / ImperasDV 經 DPI

`orca_iss` 的介面（`retire_valid/opcode/funct3/rs1a/rs2a/rda/imm/rt_result/rt_pc → mismatch/exp_result`）即 DPI 錨點：
- 以 Spike `log-commits` 解析為 DPI 函數，或接 **ImperasDV**（Core-V-Verif 官方參考模型，支援 lockstep + 覆蓋率關閉環）。
- Core-V-Verif 環境可整包引入（`core-v-verif/cv32/` 結構），ORCA 以 `cv64` 目標接入。

## 全系產品支援

同一 ISA（WMMA+SpMM, RVV1.0）貫穿 Kestrel→Garuda：riscv-dv 產生的程式在邊緣（Kestrel）到雲端（Garuda）任一層跑同一 binary；lockstep 僅驗證 ZEN++ CPU（共用核），AI 引擎以 dtype_sweep/unit TB 驗證。雲端卡的 `orca_v63_cloud_card`/`garuda` 沿用同一 ZEN++ 核 + fabric。

## 快速開始

```bash
bash dv/scripts/run_lockstep.sh            # 離線 lockstep（無外部依賴）→ TB PASS
bash dv/scripts/run_riscv_dv.sh 10 42      # 完整流程（需 riscv-dv + Spike + riscv-gcc）
```
