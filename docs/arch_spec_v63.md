# ORCA v6.3 ZEN++ 完整架構規格書

**文件版本**: v1.0
**日期**: 2026-09-07
**狀態**: 架構凍結（Architecture Freeze）
**機密等級**: 商業機密 — 限內部與簽約合作夥伴

---

## 1. 執行摘要

ORCA v6.3 ZEN++ 是 ORCA 處理器系列的旗艦世代，採用台積電 N3E（3nm 增強版）製程與 CoWoS-L 先進封裝，首次將**高效能 64 位元 RISC-V CPU** 與 **AI 加速器**整合於同一封裝內，實現 **< 50 ns** 的 CPU-AI 協同運算延遲。

### 1.1 設計目標

| 目標 | 規格 | 備註 |
|------|------|------|
| CPU 核心數 | 32（4 個 CPU Tile × 8 核心） | 每核心 4 執行緒 SMT |
| 總執行緒數 | 128 | 每 Tile 32 執行緒 |
| 指令發射寬度 | 12-wide dispatch | 業界最寬 RISC-V |
| 指令退休寬度 | 16-wide retire | 配合寬發射 |
| 目標時脈 | 3.8 GHz @ N3E | 5nm 試產為 3.2 GHz |
| AI 算力（INT8） | 512 TOPS | 4 個 AI Tile × 128 TOPS |
| AI 算力（BF16） | 256 TFLOPS | 同上 |
| HBM3 容量 | 96 GB | 4 個 AI Tile × 24 GB（3 stack × 8 GB） |
| HBM3 頻寬 | 9.8 TB/s | 819 GB/s × 12 stacks |
| CPU-AI 延遲 | < 50 ns | 同封裝直連優勢 |
| TDP | < 600 W | 全載功耗上限 |

### 1.2 關鍵創新

1. **12-wide 亂序執行管線**：目前業界最寬的 RISC-V 核心（對比 SiFive P870 為 6-wide，Ventana Veyron V2 為 8-wide）。
2. **AIX（AI eXtension）指令集**：CPU 直接以 ISA 指令驅動 AI Tile，免除傳統驅動程式 ioctl 開銷。
3. **同封裝 HBM3 + AI Tile**：AI 運算單元與高頻寬記憶體共置，消除 PCIe/DDR 瓶頸。
4. **MESI-F + CHI-E 混合一致性協議**：CPU Tile 間使用精簡 MESI-F，跨封裝採用 CHI-E 子集，兼顧效能與可擴展性。
5. **Chiplet 擴展介面（BoW）**：預留 Bunch-of-Wires 介面，支援未來多封裝擴展。

### 1.3 目標市場與競爭定位

| 市場 | 競爭對手 | ORCA v6.3 優勢 |
|------|---------|---------------|
| AI 推論伺服器 | NVIDIA H100/B200, AMD MI300X | CPU+AI 同封裝，延遲 < 50 ns |
| 高效能運算 (HPC) | Intel Xeon, AMD EPYC | RISC-V 開放 ISA，無授權限制 |
| 邊緣 AI 閘道器 | AWS Inferentia, Google TPU Edge | 開源生態，客製化彈性 |
| 雲端原生運算 | AWS Graviton, Ampere Altra | 128 執行緒高密度 |

---

## 2. 系統架構總覽

### 2.1 頂層區塊圖

```
┌─────────────────────────────────────────────────────────────────┐
│                     ORCA v6.3 SoC Package                       │
│                     (CoWoS-L, ~80mm × 80mm)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────┐ │
│  │  CPU Tile 0 │  │  CPU Tile 1 │  │  CPU Tile 2 │  │CPU Tile3│ │
│  │  8C/32T     │  │  8C/32T     │  │  8C/32T     │  │ 8C/32T  │ │
│  │  12-wide    │  │  12-wide    │  │  12-wide    │  │ 12-wide │ │
│  │  64MB L3    │  │  64MB L3    │  │  64MB L3    │  │ 64MB L3 │ │
│  │  (+V-Cache) │  │  (+V-Cache) │  │  (+V-Cache) │  │(+V-Cache│ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └────┬────┘ │
│         │                │                │              │      │
│  ───────┴────────────────┴────────────────┴──────────────┴────  │
│              Coherent Mesh NoC (CHI-E subset)                   │
│         │                │                │              │      │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐  ┌────┴────┐ │
│  │  AI Tile 0  │  │  AI Tile 1  │  │  AI Tile 2  │  │AI Tile 3│ │
│  │  64×64 PE   │  │  64×64 PE   │  │  64×64 PE   │  │ 64×64 PE│ │
│  │  128 TOPS   │  │  128 TOPS   │  │  128 TOPS   │  │128 TOPS │ │
│  │  HBM3 ×3    │  │  HBM3 ×3    │  │  HBM3 ×3    │  │ HBM3 ×3 │ │
│  │  (24 GB)    │  │  (24 GB)    │  │  (24 GB)    │  │ (24 GB) │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              IO Die / Uncore                             │   │
│  │  PCIe Gen6 ×16  │  DDR5-6400 ×4ch  │  BoW Chiplet IF    │   │
│  │  JTAG/Debug     │  Clock/PLL       │  Power Management  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 封裝技術

| 項目 | 規格 |
|------|------|
| 封裝類型 | TSMC CoWoS-L（2.5D 中介層） |
| CPU Die | 4 × N3E die（每 die 8 核心） |
| AI Die | 4 × N5P die（每 die 128 TOPS） |
| HBM3 | 12 stacks（每 AI die 3 stacks） |
| IO Die | 1 × N6 die（PCIe、DDR5、BoW） |
| V-Cache | 可選：每 CPU Tile 增加 96 MB（3D 堆疊） |
| 中介層 | Silicon Interposer，RDL 4 層 |
| 封裝尺寸 | ~80 × 80 mm |

### 2.3 時脈與功耗域

| 域 | 時脈 | 電壓 | 備註 |
|----|------|------|------|
| CPU Core | 3.8 GHz（目標） | 0.85–1.05 V DVFS | 每 Tile 獨立 DVFS |
| NoC Mesh | 1.6 GHz | 0.85 V | 固定 |
| AI Tile | 1.0 GHz | 0.80–0.95 V DVFS | 每 Tile 獨立 |
| HBM3 PHY | 3.2 GHz DDR | 1.1 V | JEDEC 標準 |
| IO (PCIe/DDR5) | 各協議標準 | 0.8–1.1 V | SerDes 獨立 |

---

## 3. CPU 微架構（ZEN++）

### 3.1 管線總覽

```
┌──────────────────────────────────────────────────────────────────┐
│                     ZEN++ Pipeline (12-wide)                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐           │
│  │ IFU  │──→│ IDU  │──→│ RNU  │──→│ ISU  │──→│ EXU  │           │
│  │ 12-wide│  │12-wide│  │12-wide│  │12-wide│  │16 FU │           │
│  │ TAGE  │   │decode│   │rename│   │sched │   │exec  │           │
│  │ 64KB  │   │RVC   │   │SMT   │   │OoO   │   │      │           │
│  │ I$    │   │uop Q │   │409 PRF│  │512 ROB│  │      │           │
│  └──────┘   └──────┘   └──────┘   └──────┘   └──┬───┘           │
│                                                  │              │
│  ┌───────────────────────────────────────────────┴───────────┐  │
│  │                    CMT (16-wide retire)                    │  │
│  │              ROB drain / Exception / Flush                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Memory Subsystem                            │   │
│  │  L1I 64KB 8-way  │  L1D 48KB 12-way  │  L2 2MB 16-way   │   │
│  │  64 MSHR         │  4 LD + 4 ST/cyc  │  512-entry DTLB  │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 前端（IFU）

| 單元 | 規格 | 說明 |
|------|------|------|
| 取指寬度 | 12 指令/週期 | 64B fetch block，RVC 解壓後最多 12 條 |
| 分支預測器 | TAGE（Tagged Geometric） | 主預測器，16 級歷史長度 |
| BTB | 8K entry，4-way | 分支目標緩衝 |
| RAS | 32 entry | 返回位址堆疊 |
| 間接預測 | ITTAGE | 間接跳轉專用 |
| I-Cache | 64 KB，8-way | 64B line，虛擬索引實體標籤 |
| ITLB | 64 entry 全相聯 | 4KB/2MB/1GB 頁面 |
| 取指佇列 | 128 µop | 解耦前端與後端 |

**分支預測準確率目標**：> 97%（SPECint2017 平均）

### 3.3 解碼器（IDU）

| 單元 | 規格 |
|------|------|
| 解碼寬度 | 12 指令/週期 |
| RVC 支援 | 完整 RVC 解壓（16-bit → 32-bit） |
| 指令類型 | RV64I/M/A/F/D/C/V + AIX 自定義擴展 |
| µop 展開 | 複雜指令（如 LR/SC、AMO）展開為多 µop |
| µop Queue | 6 佇列 × 32 entry（SMT 4 執行緒共享） |

**AIX 指令解碼**：`aix.*` 指令解碼為特殊 µop，攜帶 `aix_op` 操作碼（GEMM/ATTN/SPARSE 等）、3 個 TDB 索引（`aix_tdb0/1/2`）、以及 `aix_flags`（dtype、sparse mode）。

### 3.4 重命名與發射（RNU）

| 單元 | 規格 |
|------|------|
| 物理暫存器 | 409 個（384 通用 + 25 保留） |
| PRF | Integer PRF 409 × 64-bit；Vector PRF 256 × 256-bit |
| SMT 支援 | 4 執行緒，每執行緒獨立 RAT |
| RAT | 32 entry × 4 thread（Integer）+ 32 entry × 4 thread（Vector） |
| Freelist | 409 entry，banked 設計 |
| 重命名寬度 | 12 µop/週期 |
| Checkpoint | 分支預測點自動 checkpoint（最多 64 個） |

### 3.5 調度器（ISU）

| 單元 | 規格 |
|------|------|
| 調度佇列 | Integer SQ 96 entry；FP/Vec SQ 64 entry；Memory SQ 96 entry |
| 喚醒機制 | 2-level wakeup（predicted + actual） |
| 年齡矩陣 | 96×96 priority matrix |
| 發射寬度 | 12 µop/週期（6 INT + 4 MEM + 2 FP/Vec） |
| 投機調度 | Load 可提前於未知位址 Store（memory disambiguation） |

### 3.6 執行單元（EXU）

| FU 類型 | 數量 | 延遲 | 支援操作 |
|---------|------|------|---------|
| Integer ALU | 4 | 1 cycle | ADD/SUB/Logic/Shift |
| Branch | 2 | 1 cycle | 條件跳轉、比較 |
| Multiply | 2 | 3 cycle | IMUL/MULH（64×64） |
| Divide | 1 | 8–35 cycle | IDIV/IREM（可提前結束） |
| Load AGU | 4 | 1 cycle | 位址計算 |
| Store AGU | 4 | 1 cycle | 位址計算 + 資料寫入 |
| FP32/64 FMA | 2 | 4 cycle | 完整 IEEE 754 |
| FP Convert | 1 | 2–6 cycle | INT↔FP、FP↔FP |
| Vector ALU | 2 | 1–4 cycle | RVV 1.0（VLEN=256） |
| **AIX Dispatch** | **1** | **2 cycle** | **AIX 指令派發至 AI Tile** |

### 3.7 記憶體子系統（LSU + Cache）

| 層級 | 容量 | 組相聯 | 延遲 | 頻寬 |
|------|------|--------|------|------|
| L1 I$ | 64 KB | 8-way | 4 cycle | 64B/cycle |
| L1 D$ | 48 KB | 12-way | 5 cycle | 4 LD + 4 ST/cycle |
| L2 | 2 MB | 16-way | 14 cycle | 64B/cycle |
| L3 (per tile) | 64 MB | 16-way | ~50 cycle | 128B/cycle |
| L3 + V-Cache | 64+96 MB | — | ~55 cycle | 同上 |
| DDR5 (4ch) | — | — | ~80 ns | 204.8 GB/s |
| HBM3 (12 stacks) | 96 GB | — | ~120 ns | 9.8 TB/s |

**MSHR**: L1D 64 entry，L2 128 entry（追蹤 outstanding miss）

**預取器**：
- Stride prefetcher（L1/L2）
- Stream prefetcher（L2）
- Spatial prefetcher（L2，相鄰 line）
- AI-aware prefetcher（HBM3 → L2，學習 AI Tile 存取模式）

### 3.8 退休與例外（CMT）

| 單元 | 規格 |
|------|------|
| ROB | 512 entry（每 SMT 執行緒 128 entry 動態分割） |
| 退休寬度 | 16 µop/週期 |
| 例外處理 | 精確例外（precise exception），支援除錯模式 |
| Store Buffer | 128 entry，退休後寫入記憶體 |
| Flush 類型 | 分支 mispredict、例外、AIX trap |

### 3.9 SMT-4 設計

ZEN++ 支援 4 執行緒同步多執行緒（SMT-4）：

| 資源 | 分割策略 |
|------|---------|
| 取指 | Round-robin（每週期 1 執行緒，每 4 週期循環） |
| 解碼/重命名 | 每週期處理 1 執行緒（12-wide 完整利用） |
| ROB | 動態分割（128 entry/thread，可傾斜） |
| PRF | 共享（物理暫存器池） |
| L1 Cache | 共享（VIPT，thread-agnostic） |
| TLB | Partitioned（每 thread 專屬 ASID） |

**SMT 效能目標**：4-thread 相對 1-thread 效能提升 > 2.5×（SPECrate）

---

## 4. AI 加速器微架構（ORCA-NPU v3）

### 4.1 AI Tile 總覽

```
┌──────────────────────────────────────────────────────────────┐
│                    AI Tile (ORCA-NPU v3)                     │
│                    128 TOPS INT8 @ 1 GHz                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐   ┌──────────────────────────────────────┐    │
│  │ AIX      │   │         GSCU (Global Scheduling      │    │
│  │ Interface│──→│         & Control Unit)              │    │
│  │ (CPU)    │   │  指令佇列 64 entry │ TDB 16 entry    │    │
│  └──────────┘   └──────────┬───────────────────────────┘    │
│                            │                                │
│           ┌────────────────┼────────────────┐               │
│           │                │                │               │
│     ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴─────┐          │
│     │  Cluster 0│   │  Cluster 1│...│ Cluster 15│          │
│     │ 4×CU      │   │ 4×CU      │   │ 4×CU      │          │
│     │ (64×64 PE)│   │ (64×64 PE)│   │ (64×64 PE)│          │
│     └───────────┘   └───────────┘   └───────────┘          │
│           │                │                │               │
│  ─────────┴────────────────┴────────────────┴─────────────  │
│              AI L2 SRAM (32 MB, 16 banks)                    │
│                            │                                │
│  ┌─────────────────────────┴───────────────────────────┐    │
│  │              HBM3 Controller ×3                      │    │
│  │              3 stacks × 8 GB = 24 GB                 │    │
│  │              819 GB/s × 3 = 2.46 TB/s                │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Attention Engine (Transformer 硬體加速)              │   │
│  │  Softmax / LayerNorm / Residual / GELU               │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Tile NoC Interface (連接 Coherent Mesh)              │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 計算單元（CU）與脈動陣列

| 項目 | 規格 |
|------|------|
| 每 Tile Cluster 數 | 16 |
| 每 Cluster CU 數 | 4 |
| 每 CU PE 陣列 | 64×64 脈動陣列 |
| 總 PE 數 | 16 × 4 × 4096 = 262,144 PE |
| 峰值 INT8 | 262,144 × 2 ops × 1 GHz / 4 tile = **128 TOPS/tile** |
| 支援精度 | INT8 / INT4 / BF16 / FP16 / FP32 / FP8 |
| 稀疏支援 | 2:4 結構化稀疏（2× 有效算力） |
| 權重緩存 | 每 CU 512 KB（Weight Buffer） |
| 啟動緩存 | 每 CU 256 KB（Activation Buffer） |

**資料流**：Weight-Stationary（權重駐留 PE，activation 流動）

### 4.3 AIX 指令集

CPU 透過 AIX 指令直接控制 AI Tile，無需驅動程式中介。

| 指令 | 功能 | 說明 |
|------|------|------|
| `aix.gemm` | 矩陣乘 | A[M,K] × B[K,N] → C[M,N] |
| `aix.attn` | Attention | Q×K^T → softmax → ×V |
| `aix.sparse_mm` | 稀疏矩陣乘 | 2:4 structured sparse GEMM |
| `aix.conv` | 卷積 | im2col + GEMM |
| `aix.sync` | 同步 | 等待 AI Tile 完成（barrier） |
| `aix.cfg` | 配置 | 設定 dtype、tile 尺寸、sparse mode |
| `aix.dma_ld` | DMA 載入 | HBM3 → AI L2 |
| `aix.dma_st` | DMA 儲存 | AI L2 → HBM3 |

**TDB（Tile Descriptor Block）**：每個 AIX 指令攜帶 3 個 TDB 索引，TDB 定義矩陣的基底位址、維度（M/N/K）、stride、dtype。CPU 在執行 AIX 指令前，以 `aix.cfg` 預先填充 TDB。

### 4.4 全域調度與控制單元（GSCU）

| 功能 | 說明 |
|------|------|
| 指令佇列 | 64 entry，FIFO |
| TDB 檔案 | 16 entry，硬體管理 |
| 相依性追蹤 | TDB busy bit，自動 stall |
| Cluster 分派 | Round-robin 至空閒 Cluster |
| 完成中斷 | 聚合至 CPU（MSI-X 或 AIX sync） |
| QoS | 4 級優先權， starvation 防止 |

### 4.5 Attention 硬體加速引擎

專為 Transformer 推論優化的專用管線：

| 階段 | 硬體支援 |
|------|---------|
| Q×K^T | 脈動陣列 GEMM |
| Softmax | 線性近似 LUT + Newton-Raphson 迭代 |
| ×V | 脈動陣列 GEMM |
| LayerNorm | 均值/方差計算單元 |
| Residual Add | 向量加法器 |
| GELU | 分段線性 LUT |
| KV-Cache 管理 | HBM3 指標追蹤，自動 append |

**效能目標**：BERT-Large single layer < 5 µs（batch=1, seq=512）

### 4.6 HBM3 子系統

| 項目 | 規格 |
|------|------|
| 標準 | JEDEC HBM3 |
| Stack 數 | 3 per AI Tile（12 total） |
| 容量 | 8 GB/stack（24 GB/tile，96 GB total） |
| 頻寬 | 819 GB/s/stack（2.46 TB/s/tile） |
| Pseudo-channel | 2 per stack |
| Bank 數 | 32 per pseudo-channel |
| 刷新 | 自動 + 溫度感知 |
| ECC | On-die ECC + link ECC |
| 省電 | Self-refresh、power-down、溫度降頻 |

### 4.7 AI L2 SRAM

| 項目 | 規格 |
|------|------|
| 容量 | 32 MB |
| Bank 數 | 16（獨立存取） |
| 頻寬 | 128 B/cycle/bank |
| ECC | SECDED |
| Scrubbing | 背景 scrub（可配置速率） |
| 分割 | 可配置為 unified 或 per-cluster |

---

## 5. 互連架構

### 5.1 Coherent Mesh NoC

| 項目 | 規格 |
|------|------|
| 拓撲 | 2D Mesh（4×2 節點：4 CPU Tile + 4 AI Tile） |
| 協議 | AMBA CHI-E 子集（CPU 間） + 自定義（CPU↔AI） |
| Flit 寬度 | 512-bit data + 32-bit header |
| 虛擬通道 | 4 VC（REQ/RSP/SNP/DATA） |
| 時脈 | 1.6 GHz（獨立時脈域） |
| 路由 | X-Y dimension order |
| 流量控制 | Credit-based |

### 5.2 一致性協議

**CPU Tile 間**：MESI-F（Modified/Exclusive/Shared/Invalid/Forward）
- Forward 狀態減少目錄查詢延遲
- Snoop filter：每 Tile 8K entry，覆蓋 L1+L2

**CPU ↔ AI Tile**：自定義輕量協議
- AI L2 不參與 CPU 一致性域（scratchpad 語義）
- CPU 透過 AIX 指令顯式管理 AI 資料生命週期
- HBM3 由 AI Tile 獨佔（CPU 可經 NoC 存取，但不快取）

### 5.3 BoW Chiplet 擴展介面

| 項目 | 規格 |
|------|------|
| 標準 | Bunch of Wires（BoW）|
| 通道數 | 8 TX + 8 RX |
| 資料率 | 16 GT/s per wire |
| 頻寬 | 32 GB/s per direction |
| 用途 | 未來多封裝擴展（2P/4P 伺服器） |

---

## 6. RTL 實作規格

### 6.1 模組層次與檔案清單

```
orca_v63/
├── rtl/
│   ├── common/
│   │   └── orca_pkg.sv                # 全域套件（參數、型別、指令定義）
│   │
│   ├── soc/
│   │   └── orca_v63_soc.sv            # SoC 頂層
│   │
│   ├── cpu/
│   │   ├── orca_v63_cpu_tile.sv       # CPU Tile 頂層
│   │   ├── orca_v63_cpu_core.sv       # CPU Core 頂層
│   │   ├── frontend/
│   │   │   ├── ifu_bpu.sv             # 分支預測器（TAGE）
│   │   │   ├── ifu_fetch.sv           # 取指單元
│   │   │   ├── ifu_btb.sv             # BTB
│   │   │   └── ifu_tlb.sv             # ITLB
│   │   ├── decode/
│   │   │   ├── idu_decoder.sv         # 解碼器
│   │   │   ├── idu_uop_queue.sv       # µop 佇列
│   │   │   └── idu_rvc_expand.sv      # RVC 解壓
│   │   ├── rename/
│   │   │   ├── rnu_rat.sv             # 暫存器別名表
│   │   │   ├── rnu_freelist.sv        # 自由暫存器池
│   │   │   └── rnu_remap.sv           # 重命名控制
│   │   ├── scheduler/
│   │   │   ├── isu_int.sv             # Integer 調度器
│   │   │   ├── isu_fp.sv              # FP/Vec 調度器
│   │   │   ├── isu_mem.sv             # Memory 調度器
│   │   │   └── isu_wake.sv            # 喚醒邏輯
│   │   ├── execution/
│   │   │   ├── exu_alu.sv             # Integer ALU
│   │   │   ├── exu_mul.sv             # 乘法器
│   │   │   ├── exu_fpu.sv             # 浮點單元
│   │   │   ├── exu_vec.sv             # 向量單元（RVV）
│   │   │   ├── exu_bru.sv             # 分支單元
│   │   │   └── exu_crypto.sv          # 加密加速
│   │   ├── memory/
│   │   │   ├── lsu_ld.sv              # Load 單元
│   │   │   ├── lsu_st.sv              # Store 單元
│   │   │   ├── lsu_dtlb.sv            # DTLB
│   │   │   ├── lsu_mshr.sv            # MSHR
│   │   │   └── lsu_dcache.sv          # L1 D-Cache
│   │   ├── cache/
│   │   │   ├── icache.sv              # L1 I-Cache
│   │   │   ├── icache_tag.sv          # I$ Tag
│   │   │   ├── dcache.sv              # L1 D-Cache (wrapper)
│   │   │   ├── dcache_tag.sv          # D$ Tag
│   │   │   ├── l2cache.sv             # L2 Cache
│   │   │   └── l3cache.sv             # L3 Cache
│   │   └── commit/
│   │       ├── cmt_rob.sv             # ROB
│   │       ├── cmt_archreg.sv         # 架構暫存器
│   │       └── cmt_trap.sv            # 例外/中斷
│   │
│   ├── ai/
│   │   ├── orca_v63_ai_tile.sv        # AI Tile 頂層
│   │   ├── ctrl/
│   │   │   ├── npu_gscu.sv            # GSCU
│   │   │   ├── npu_dma.sv             # AI DMA
│   │   │   └── npu_aix_intf.sv        # AIX 介面
│   │   ├── cluster/
│   │   │   ├── npu_cluster.sv         # Cluster（4×CU）
│   │   │   └── npu_cu.sv              # 計算單元
│   │   ├── pe/
│   │   │   ├── npu_systolic.sv        # 64×64 脈動陣列
│   │   │   ├── npu_pe.sv              # 單一 PE
│   │   │   └── npu_acc.sv             # 累加器
│   │   ├── attention/
│   │   │   └── npu_attn_engine.sv     # Attention 引擎
│   │   ├── memory/
│   │   │   ├── npu_l2_sram.sv         # AI L2 SRAM
│   │   │   ├── npu_hbm3_ctrl.sv       # HBM3 控制器
│   │   │   └── npu_hbm3_phy.sv        # HBM3 PHY
│   │   └── noc/
│   │       └── npu_tile_noc.sv        # AI Tile NoC 介面
│   │
│   ├── noc/
│   │   ├── orca_noc_router.sv         # Mesh 路由器
│   │   ├── orca_noc_link.sv           # 鏈路（含 flow control）
│   │   ├── orca_chi_coh.sv            # CHI 一致性控制器
│   │   └── orca_bow_link.sv           # BoW chiplet 介面
│   │
│   └── pad/
│       ├── ddr5_ctrl.sv               # DDR5 控制器
│       ├── pcie_gen6.sv               # PCIe Gen6 控制器
│       ├── gpio_pad.sv                # GPIO
│       └── clock_gate.sv              # Clock gating
│
├── tb/
│   ├── cpu_tile_tb/                   # CPU UVM 測試平台
│   │   ├── orca_cpu_agent.sv
│   │   ├── orca_cpu_sequence.sv
│   │   ├── orca_cpu_env.sv
│   │   ├── orca_cpu_test.sv
│   │   └── tb_top.sv
│   ├── ai_tile_tb/                    # AI C++ DPI 參考模型
│   │   ├── ai_tile_ref_model.cpp
│   │   └── ai_tile_ref_model.h
│   ├── sva/                           # SystemVerilog Assertions
│   │   ├── orca_sva_rob.sv
│   │   ├── orca_sva_cache.sv
│   │   └── orca_sva_noc.sv
│   └── dpi/                           # DPI-C 介面
│       └── cpu_ref_model.cpp
│
├── syn/
│   ├── cpu_tile.tcl                   # DC synthesis script
│   ├── ai_tile.tcl
│   └── fpga_build.tcl                 # Vivado FPGA build
│
├── scripts/
│   ├── vcs_compile.sh                 # VCS 編譯
│   ├── run_regression.sh              # 回歸測試
│   └── gen_filelist.sh                # File list 生成
│
├── ci/
│   ├── github_actions.yml             # GitHub Actions CI
│   └── jenkins/                       # Jenkins pipeline
│
└── docs/
    └── arch_spec_v63.md               # 本文件
```

### 6.2 關鍵模組介面定義

#### `orca_pkg.sv` 核心型別

```systemverilog
package orca_pkg;
  // ---- 全域參數 ----
  parameter int FETCH_WIDTH    = 12;
  parameter int ISSUE_WIDTH    = 12;
  parameter int RETIRE_WIDTH   = 16;
  parameter int ROB_ENTRIES    = 512;
  parameter int INT_SQ_ENTRIES = 96;
  parameter int MEM_SQ_ENTRIES = 96;
  parameter int FP_SQ_ENTRIES  = 64;
  parameter int PHYS_REGS      = 409;
  parameter int SMT_THREADS    = 4;

  // ---- AI Tile 參數 ----
  parameter int CLUSTERS_PER_TILE = 16;
  parameter int CUS_PER_CLUSTER   = 4;
  parameter int PE_ARRAY_DIM      = 64;
  parameter int AI_L2_SIZE_MB     = 32;
  parameter int HBM3_STACKS       = 3;
  parameter int HBM3_CAPACITY_GB  = 24;

  // ---- AIX 指令 opcode ----
  typedef enum logic [6:0] {
    AIX_OP_GEMM      = 7'h01,
    AIX_OP_ATTN      = 7'h02,
    AIX_OP_SPARSE_MM = 7'h03,
    AIX_OP_CONV      = 7'h04,
    AIX_OP_SYNC      = 7'h05,
    AIX_OP_CFG       = 7'h06,
    AIX_OP_DMA_LD    = 7'h07,
    AIX_OP_DMA_ST    = 7'h08
  } aix_opcode_t;

  // ---- AIX TDB ----
  typedef struct packed {
    logic [63:0] base_addr;
    logic [15:0] dim_m;
    logic [15:0] dim_n;
    logic [15:0] dim_k;
    logic [31:0] stride;
    logic [2:0]  dtype;
    logic        sparse_en;
  } aix_tdb_t;

  // ---- µop ----
  typedef struct packed {
    logic [63:0] pc;
    logic [4:0]  rs1, rs2, rd;
    logic [63:0] imm;
    logic [6:0]  opcode;
    logic        is_rvc;
    logic        is_aix;
    aix_opcode_t aix_op;
    logic [3:0]  aix_tdb0, aix_tdb1, aix_tdb2;
    logic [7:0]  aix_flags;
    logic [1:0]  smt_tid;
    logic [8:0]  rob_idx;
    // ... (其餘欄位)
  } uop_t;
endpackage
```

### 6.3 SoC 頂層介面

```systemverilog
module orca_v63_soc (
  // 系統介面
  input  logic        clk_sys,      // 3.2 GHz
  input  logic        clk_noc,      // 1.6 GHz (async)
  input  logic        rst_n,

  // DDR5 記憶體介面 (4 channels)
  output logic [3:0]  ddr5_ck_t, ddr5_ck_c, ddr5_cs_n,
  inout  logic [3:0]  ddr5_dqs_t, ddr5_dqs_c,
  inout  logic [63:0] ddr5_dq,
  output logic [15:0] ddr5_addr,
  output logic [1:0]  ddr5_ba,
  output logic        ddr5_act_n,

  // HBM3 介面 (per AI tile, 3 stacks each)
  output logic [11:0] hbm3_ck_t, hbm3_ck_c, hbm3_cs_n,
  inout  logic [11:0] hbm3_dqs_t, hbm3_dqs_c,
  inout  logic [1535:0] hbm3_dq,  // 4 tiles × 3 stacks × 128-bit

  // PCIe Gen6 x16
  output logic        pcie_tx_p, pcie_tx_n,
  input  logic        pcie_rx_p, pcie_rx_n,
  input  logic        pcie_refclk_p, pcie_refclk_n,

  // BoW Chiplet 擴展介面
  output logic [7:0]  bow_tx_data, bow_tx_clk,
  input  logic [7:0]  bow_rx_data, bow_rx_clk,

  // JTAG / Debug
  input  logic        jtag_tck, jtag_tms, jtag_tdi,
  output logic        jtag_tdo,

  // 中斷
  input  logic        ext_irq_n,
  output logic        nmi_out
);
```

### 6.4 綜合策略與 SDC 約束摘要

```tcl
# 主時脈
 create_clock -name clk_sys -period 0.3125 [get_ports clk_sys]  ;# 3.2 GHz
 create_clock -name clk_noc -period 0.625  [get_ports clk_noc]   ;# 1.6 GHz
 create_clock -name clk_ai  -period 1.000  [get_pins u_clock_gen/clk_ai]

# CDC
 set_clock_groups -asynchronous    -group {clk_sys clk_cpu}    -group {clk_noc}    -group {clk_ai clk_hbm3}

# 關鍵路徑約束
 set_max_delay 0.250 -from [get_cells */int_prf[*]] -to [get_cells */u_alu[*]]

# 多週期路徑
 set_multicycle_path 3 -setup -from [get_cells */u_mul*] -to [get_cells */u_rob]
 set_multicycle_path 2 -hold  -from [get_cells */u_mul*] -to [get_cells */u_rob]

# 面積/功耗
 set_max_area 2000000
 set_max_total_power 600 [get_designs orca_v63_soc]
```

### 6.5 模組實作優先順序

| 優先級 | 模組 | 估計工時 | 相依性 |
|--------|------|---------|--------|
| P0 | orca_pkg.sv | 1 天 | 無 |
| P0 | ifu_fetch + icache | 2 週 | pkg |
| P0 | rnu_remap + cmt_rob | 2 週 | pkg |
| P1 | exu_alu + exu_fpu | 1 週 | pkg |
| P1 | lsu_ld + lsu_st + dcache | 3 週 | pkg |
| P1 | npu_gscu + npu_dma | 2 週 | pkg |
| P2 | npu_systolic + npu_pe | 3 週 | pkg |
| P2 | npu_hbm3_ctrl | 2 週 | pkg |
| P2 | orca_noc_mesh | 2 週 | pkg |
| P3 | aix_tile_agg + aix_core_intf | 1 週 | CPU+AI |
| P3 | orca_v63_soc (頂層整合) | 1 週 | 全部 |

### 6.6 驗證策略

| 層級 | 方法 | 工具 | 目標 |
|------|------|------|------|
| 單元級 | UVM | Synopsys VCS / Cadence Xcelium | 每個模組獨立驗證 |
| 子系統級 | C++ reference model + DPI | Verilator / VCS | CPU core vs Spike, AI vs PyTorch |
| SoC 級 | FPGA emulation | AMD/Xilinx VCU128 | 4-core 縮減版，100 MHz |
| 軟體協同 | Linux boot + benchmark | QEMU + RTL co-sim | 啟動 Linux，執行 SPEC / MLPerf |
| 效能驗證 | Performance monitor | 自製 perf tool | CPI, cache miss rate, AI utilization |

---

## 7. 開發路線圖與時程

### 7.1 總體時間線（2026 Q4 – 2028 Q4）

```
2026        2027                                    2028
Q4  |  Q1      Q2      Q3      Q4  |  Q1      Q2      Q3      Q4
────┼────────────────────────────────┼────────────────────────────────
    │  [==== 架構凍結 ====]          │
    │       [======== RTL 實作 ======]
    │              [==== 驗證與效能調校 ====]
    │                      [====== FPGA 原型 ======]
    │                              [==== 試產流片 (5nm) ====]
    │                                      [==== 量產流片 (3nm) ====]
    │                                              [== 商用出貨 ==]
────┼────────────────────────────────┼────────────────────────────────
M0  M3      M6      M9      M12     M15     M18     M21     M24
```

### 7.2 里程碑定義

| 里程碑 | 日期 | 名稱 | 交付物 | 成功標準 |
|--------|------|------|--------|---------|
| M0 | 2026/10 | 專案啟動 | 架構規格書 v1.0、RTL 檔案樹 | 核心團隊到位 |
| M3 | 2027/01 | 架構凍結 | 完整微架構規格、介面協議凍結 | 所有介面簽核完成 |
| M6 | 2027/04 | RTL Alpha | 100% 模組 stub 完成 | 通過 lint + smoke test |
| M9 | 2027/07 | RTL Beta | 所有功能單元實作完成 | 可啟動 bare-metal test |
| M12 | 2027/10 | 驗證凍結 | 90%+ 功能覆蓋率 | 通過 gate-level simulation |
| M15 | 2028/01 | FPGA 原型驗證 | 4-core 縮減版啟動 Linux | 實測 IPC > 4.0 |
| M18 | 2028/04 | 5nm 試產流片 | MPW shuttle | 晶片回片，啟動 bring-up |
| M21 | 2028/07 | 試產驗證 | 矽後驗證完成 | 時脈達成 2.5 GHz |
| M24 | 2028/10 | 3nm 量產流片 | 完整 32C + 4 AI Tile | 量產 wafer 下單 |
| M27 | 2029/01 | 商用出貨 | 參考設計板、驅動、SDK | 首批客戶出貨 |

### 7.3 各階段工作分解

#### Phase 1: 架構與規格（M0–M3）

| 工作包 | 工時 | 交付物 |
|--------|------|--------|
| ISA 擴展定稿（AIX + ZEN++ 自定義） | 4 週 | orca_isa_v63.pdf |
| 微架構規格凍結 | 6 週 | orca_uarch_v63.pdf |
| 記憶體一致性協議定義 | 3 週 | orca_coh_spec_v63.pdf |
| HBM3 PHY 介面規格 | 2 週 | orca_hbm3_intf_v63.pdf |
| 功耗/熱模型初版 | 3 週 | orca_thermal_model_v63.xlsx |
| 軟體介面定義 | 4 週 | orca_aix_abi_v63.h |

**關鍵決策點（M3 Go/No-Go）**：
- 5nm 製程合作夥伴確認（TSMC / Samsung）
- HBM3 供應商確認（SK Hynix 優先，Samsung 備案）
- EDA 工具授權到位
- 核心團隊招募完成（> 30 人）

#### Phase 2: RTL 實作（M3–M9）

- CPU Tile RTL: M3–M8（前端 → 執行 → 記憶體 → 快取）
- AI Tile RTL: M4–M9（GSCU → PE 陣列 → HBM3 → Attention）
- NoC / SoC 整合: M7–M9

#### Phase 3: 驗證與效能調校（M6–M12）

- UVM testbench 框架: M6–M7
- 模組級驗證: M7–M10
- SoC 整合驗證: M10–M11
- 效能建模校準: M9–M11
- Gate-Level Sim: M11–M12

**驗證覆蓋率目標**：
- 功能覆蓋率: > 95%（模組級）、> 90%（系統級）
- 程式碼覆蓋率: > 98%（行覆蓋）、> 95%（FSM/分支/表達式）
- 斷言: > 500 個 SVA

#### Phase 4: FPGA 原型驗證（M10–M15）

- 縮減版規格（4C + 1 AI Tile）
- VCU128 映射
- Linux kernel port + AIX 驅動
- SPECint / AI 推論基準測試
- **目標: IPC > 4.0 @ 100 MHz FPGA**

#### Phase 5: 矽實現（M12–M21）

- 5nm 試產: M12–M18（MPW shuttle, TSMC N5P）
- 3nm 量產: M18–M24（TSMC N3E, CoWoS-L）

### 7.4 人力資源規劃

| 職能 | 人數 | 進場時間 | 峰值負荷期 |
|------|------|---------|-----------|
| 首席架構師 | 2 | M0 | 全程 |
| CPU 微架構工程師 | 8 | M0 | M3–M9 |
| AI 加速器工程師 | 6 | M0 | M4–M10 |
| 記憶體/互連工程師 | 4 | M0 | M5–M11 |
| RTL 設計工程師 | 10 | M3 | M3–M9 |
| 驗證工程師（UVM） | 8 | M6 | M6–M12 |
| 實體設計工程師 | 6 | M12 | M12–M21 |
| DFT/測試工程師 | 2 | M14 | M14–M18 |
| 封裝工程師 | 2 | M12 | M12–M24 |
| 軟體/編譯器工程師 | 4 | M3 | M3–M24 |
| 韌體/驅動工程師 | 2 | M10 | M10–M24 |
| 專案管理/品質 | 1 | M0 | 全程 |
| **總計** | **55** | | |

### 7.5 預算估算（USD）

| 項目 | 成本 |
|------|------|
| 人力成本 | $13.11M |
| IP 與工具授權 | $8.30M |
| 流片與封裝 | $24.00M |
| 其他（FPGA、雲端、差旅、應急儲備 10%） | $5.75M |
| **總計** | **$51.16M** |

### 7.6 風險矩陣

| 風險 | 機率 | 衝擊 | 風險值 | 緩解措施 | 應急計畫 |
|------|------|------|--------|---------|---------|
| 3nm 流片失敗 | 中 (30%) | 致命 (9) | 2.7 | 5nm 試產先行驗證 | 降規至 2.8 GHz、減少 SMT 至 2-way |
| HBM3 供應短缺 | 中 (25%) | 高 (7) | 1.75 | 雙供應商策略 | 改用 LPDDR5X |
| 關鍵人才流失 | 中 (20%) | 高 (8) | 1.6 | 競業條款、股票選擇權 | 與學術機構合作 |
| RISC-V 軟體生態延遲 | 高 (40%) | 中 (6) | 2.4 | 同步投資編譯器與驅動 | QEMU 加速層 |
| 競爭對手搶先 | 高 (50%) | 中 (6) | 3.0 | 差異化定位（超低延遲） | 轉向邊緣 AI 閘道器 |
| 資金鏈斷裂 | 低 (15%) | 致命 (10) | 1.5 | 分階段融資 | 策略投資/政府補助 |

### 7.7 競爭對比時間線

| 產品 | 發表時間 | 量產時間 | ORCA v6.3 差距 |
|------|---------|---------|---------------|
| NVIDIA Blackwell | 2024 | 2025 | +1.5 年落後，但整合 CPU 差異化 |
| AMD MI350X | 2025 | 2026 | +1 年落後，但 HBM3 頻寬更高 |
| Intel Falcon Shores | 2025 | 2026 | 同時間窗口 |
| AWS Trainium3 | 2025 | 2026 | 同時間窗口，但 AWS 僅自用 |
| Ventana Veyron V2 | 2023 (paper) | 2027 (宣稱) | 可能同時量產，但無 AI |
| SiFive P550 後繼 | 2024 | 2025 | +1 年落後，但無 AI 整合 |
| 阿里雲 C930 | 2025 | 2026 | 同時間窗口，但無 HBM3/Chiplet |

**ORCA v6.3 的時間窗口優勢**：
- 2028 年將是 RISC-V 高性能核心 + AI 整合的**首波量產窗口**
- 若準時交付，將是**全球首款** 12-wide SMT-4 RISC-V + HBM3 AI 同封裝處理器

### 7.8 成功指標（KPI）

| 指標 | 目標 | 驗證方法 |
|------|------|---------|
| SPECint2017 (rate) | > 5.0 / core | 矽後實測 |
| SPECfp2017 (rate) | > 6.0 / core | 矽後實測 |
| MLPerf Inference (ResNet-50) | > 100,000 img/s @ INT8 | 矽後實測 |
| LLM 推論延遲（Llama-3 70B） | < 20 ms/token | 矽後實測 |
| CPU-AI 協同延遲 | < 50 ns | FPGA 實測 |
| 功耗效率（perf/W） | > 2x vs NVIDIA H100（同製程） | 矽後實測 |
| 時脈達成率 | 3.2 GHz @ 5nm / 3.8 GHz @ 3nm | STA 簽核 |
| 良率 | > 70%（5nm 試產） | 晶圓測試 |
| 軟體就緒度 | PyTorch 原生支援、Linux mainline | 社群反饋 |

### 7.9 關鍵決策點（Go/No-Go Gates）

| 閘門 | 時間 | 決策內容 | 通過標準 |
|------|------|---------|---------|
| G0: 專案啟動 | M0 | 是否投入 v6.3 開發 | 資金到位、團隊核心 5 人到齊 |
| G1: 架構凍結 | M3 | 微架構是否凍結 | 所有介面簽核、風險評估通過 |
| G2: RTL 凍結 | M9 | 是否進入實體設計 | 90% 功能覆蓋率、無重大架構變更 |
| G3: FPGA 驗收 | M15 | 是否進入流片 | IPC > 4.0、AI 功能驗證通過 |
| G4: 5nm 試產評估 | M18 | 是否投入 3nm 量產 | 時序達成 2.5 GHz、功耗 < 200W |
| G5: 量產決策 | M22 | 是否下單 3nm 量產 | 良率 > 70%、客戶意向書 > $10M |

---

## 8. 附錄

### 8.1 術語表

| 術語 | 說明 |
|------|------|
| AIX | AI eXtension，ORCA 自定義 CPU-AI 協同指令集 |
| BoW | Bunch of Wires，chiplet 互連技術 |
| CHI-E | AMBA Coherent Hub Interface，擴展版本 |
| CU | Compute Unit，AI Tile 內計算單元 |
| GSCU | Global Scheduling and Control Unit，AI Tile 控制核心 |
| MESI-F | Modified/Exclusive/Shared/Invalid/Forward，快取一致性協議 |
| PE | Processing Element，脈動陣列基本計算單元 |
| RVV | RISC-V Vector Extension，向量擴展 |
| SMT | Simultaneous Multithreading，同步多執行緒 |
| TAGE | TAgged GEometric history length，分支預測演算法 |
| µop | Micro-operation，微操作 |
| ZEN++ | ORCA CPU 微架構代號，v6.3 世代 |

### 8.2 參考文件

- RISC-V ISA Specification, Volume I: Unprivileged ISA, Version 20240411
- RISC-V Vector Extension (RVV) Specification, Version 1.0
- AMBA CHI Architecture Specification, Issue E
- HBM3 JEDEC Standard JESD238
- UCIe Specification, Version 1.1
- TSMC N3E/N5P Design Rules (NDA)

### 8.3 修訂歷史

| 版本 | 日期 | 作者 | 變更內容 |
|------|------|------|---------|
| v0.1 | 2026-09-01 | 架構團隊 | 初稿：競爭分析 + 架構目標 |
| v0.2 | 2026-09-03 | 架構團隊 | 新增 CPU 微架構設計 |
| v0.3 | 2026-09-05 | 架構團隊 | 新增 AI 加速器設計 |
| v0.4 | 2026-09-06 | 架構團隊 | 新增 RTL stub 與規格 |
| v0.5 | 2026-09-07 | 架構團隊 | 新增路線圖與時程 |
| v1.0 | 2026-09-07 | 架構團隊 | 整合發布，所有章節凍結 |

---

> **機密聲明**：本文件包含 ORCA Inc. 商業機密與專有技術資訊。未經書面授權，禁止複製、散佈或揭露給第三方。

---
*文件結束*
