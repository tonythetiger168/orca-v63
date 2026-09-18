# ORCA v6.3 ZEN++ 完整架構規格書

> 版本: v1.0  
> 日期: 2026-09-07  
> 機密等級: 內部機密  
> 作者: ORCA 架構團隊

---

## 目錄

1. [執行摘要](#1-執行摘要)
2. [RISC-V 競爭格局分析](#2-risc-v-競爭格局分析)
3. [ZEN++ 架構目標與差異化](#3-zen-架構目標與差異化)
4. [CPU 微架構設計](#4-cpu-微架構設計)
5. [AI 加速器設計](#5-ai-加速器設計)
6. [RTL 架構規格與 Stub](#6-rtl-架構規格與-stub)
7. [開發路線圖與時程](#7-開發路線圖與時程)
8. [附錄](#8-附錄)

---

## 1. 執行摘要

ORCA v6.3 ZEN++ 是 ORCA 處理器家族的下一代旗艦設計，定位為全球首款 12-wide dispatch、4-way SMT 的 RISC-V 高性能核心，並首次在同封裝中整合 HBM3 AI 加速器（ORCA-NPU v3）。

### 1.1 核心指標

| 項目 | 規格 |
|------|------|
| CPU 核心 | 32 核（4 Tile × 8 核），4-way SMT = 128 執行緒 |
| Issue Width | 12-wide dispatch / 16-wide retire |
| 目標時脈 | 3.2 GHz (5nm) / 3.8 GHz (3nm) |
| AI 算力 | 512 TOPS INT8 / 256 TFLOPS BF16（4 AI Tile） |
| HBM3 容量 | 96 GB（4 Tile × 24 GB） |
| HBM3 頻寬 | 9.8 TB/s |
| CPU-AI 協同延遲 | < 50 ns |
| 總功耗 | 600W（基板級） |

### 1.2 差異化定位

- **全球首款** 12-wide SMT-4 RISC-V 核心
- **全球首款** RISC-V + HBM3 AI 同封裝處理器
- **業界最低** CPU-AI 協同延遲（< 50 ns vs NVIDIA H100 ~1 µs）
- **開放生態** 免 Arm/x86 授權費，可客製化 AIX 指令

---

## 2. RISC-V 競爭格局分析

### 2.1 高性能核心排名（2026 實測）

| 排名 | 核心 | 廠商 | 關鍵特性 | 實測表現 |
|------|------|------|---------|--------|
| 1 | C920v2 | 阿里雲 T-Head | 4-issue OoO, RVV 1.0, 64 核 | NPB 全面領先 |
| 2 | X60 (K1/M1) | SpacemiT | 3-issue, RVV 1.0, 256-bit 向量 | 最接近 C920v2 |
| 3 | P550 | SiFive | 3-issue OoO | 架構平衡，時脈偏低 |
| 4 | Veyron VT1/VT2 | Ventana | 宣稱 ≈ Neoverse V1/V2 | **紙上談兵，模擬數據** |
| 5 | U74 / C906 | SiFive / T-Head | In-order / 簡單 OoO | 數億級出貨，效能天花板低 |

### 2.2 共同瓶頸

- **時脈嚴重偏低**：現有 RISC-V 高性能核心最高僅 1.85 GHz，與 Arm A73 (2.0+ GHz) 差距明顯
- **軟體優化不足**：缺乏 hand-optimized RVV assembly，編譯器 tune 模型不足
- **軟體生態缺口**：伺服器軟體移植需 3–5 年

### 2.3 對 ORCA v6.3 的啟示

1. 若 v6.3 定位 12+ issue SMT 核心，市場上**無任何 RISC-V 核心達到此等級**——藍海機會
2. 必須同步投資編譯器優化與 RVV assembly 實作
3. 時脈突破 2.5+ GHz 是關鍵差異化
4. 2026–2027 年是 RISC-V 高性能核心量產關鍵窗口

---

## 3. ZEN++ 架構目標與差異化

### 3.1 設計哲學

ZEN++ 借鑒 AMD Zen 5 與 Apple M 系列的設計經驗，但針對 RISC-V ISA 進行優化：

- **寬發射 + 深緩衝**：12-wide dispatch 搭配 1K-entry ROB，隱藏記憶體延遲
- **SMT-4 最大化吞吐量**：針對雲端/容器場景優化，4-way SMT 提升 60% throughput
- **向量優先**：512-bit RVV 原生支援，2x 向量 ALU，AI 推論無需 offload
- **CPU-AI 零複製協同**：AIX 指令集擴展，共享記憶體語意，< 50 ns 延遲

### 3.2 與競品對比

| 規格 | ORCA v6.3 | AMD Zen 5 | Apple M4 | Intel Granite Rapids |
|------|-----------|-----------|----------|---------------------|
| Dispatch Width | 12 | 8 | 12 | 8 |
| SMT | 4-way | 2-way | 無 | 2-way |
| ROB | 1,024 | 768 | ~650 | ~768 |
| RVV 支援 | 512-bit | 無 | 無 | 無 |
| AI 整合 | 同封裝 HBM3 | 無 | 同封裝 LPDDR | 無 |
| ISA | RISC-V (開放) | x86 (封閉) | Arm (授權) | x86 (封閉) |

---

## 4. CPU 微架構設計

### 4.1 前端管線

#### 4.1.1 分支預測器：ORCA-BPU v3

```
ORCA-BPU v3 - 三層級混合預測架構

L0: µBTB (Micro-Branch Target Buffer)
    • 128 entries, 1-cycle latency
    • 預測無條件跳轉與返回，零氣泡

L1: TAGE-SC-L + Perceptron Hybrid
    • TAGE: 16 tables, 16K entries each, history 4~640
    • Statistical Corrector (SC): 64K entries
    • Loop Predictor (LP): 256 loops, iteration count
    • 預測精度目標: > 97% (SPECint), > 99% (loop-heavy)

L2: Indirect Target Array (ITA) + Return Address Stack
    • 4K indirect targets, 64-way RAS (per thread)
    • 間接跳轉預測精度: > 92%

特色: ML-Assisted Prefetch Hint
    • 輕量級 LSTM 推論引擎 (on-chip, 4K 參數)
    • 根據全域分支歷史預測「長跳躍」目標，輔助 I-Cache
    • 降低 15% I-Cache miss penalty
```

#### 4.1.2 取指與解碼

| 單元 | 規格 | 說明 |
|------|------|------|
| Fetch Bandwidth | 32 instructions / cycle | 8 個 4-instruction fetch blocks |
| I-Cache | 64 KB, 8-way, 64B line, 4-cycle | 雙埠設計，支援 SMT 並行取指 |
| I-TLB | 128 entries, fully associative | 每執行緒獨立，4-cycle |
| Decode | 6-wide x86-RISC-V fused decoder | 複雜指令拆為 2–4 µops |
| µop Cache | 3K entries, 8-way | 命中時繞過解碼，降低功耗 30% |
| Branch Resolution | 2-cycle (taken/not-taken) | 錯誤預測懲罰: 14 cycles |

### 4.2 重命名與調度

#### 4.2.1 實體暫存器檔案（PRF）

| PRF 類型 | 容量 | 說明 |
|---------|------|------|
| Integer PRF | 384 entries | 支援 4-way SMT × 32 arch × 3 深度 |
| Vector PRF | 512 entries | 512-bit wide, RVV 1.0 |
| FP PRF | 256 entries | 雙精度 |
| Flag/Condition | 64 entries | |
| 重命名頻寬 | 12 µops / cycle | |

#### 4.2.2 調度佇列（Issue Queues）

| 佇列類型 | 深度 | 發射寬度 | 說明 |
|---------|------|---------|------|
| Integer Scheduler | 64 entries | 6-wide | 4x ALU + 2x 分支/複雜 |
| FP/Vector Scheduler | 48 entries | 4-wide | 2x FMA + 2x vector permute |
| Load/Store Scheduler | 32 entries | 4-wide | 2x Load + 2x Store AGU |
| Memory Dependency | 48 entries | — | 記憶體消歧與順序維護 |

**總發射寬度: 16-wide (6+4+4+2 保留站發射)**

### 4.3 執行引擎

#### 4.3.1 功能單元佈局

```
Integer Cluster
    ALU0  ALU1  ALU2  ALU3    (simple: add/sub/logic/shift)
    BRU0  BRU1  MUL   DIV      (2x branch + 1x mul 3-cycle + 1x div)
    AGU0  AGU1                 (2x load/store address generation)

FP/Vec Cluster
    FMA0  FMA1                 (fp64/fp32, 4-cycle latency)
    VEC0  VEC1                 (512-bit RVV, 8x 64-bit lanes)
    PERM0 PERM1                (vector permute/cross-lane)
    CRYPTO                     (AES/SHA/SM4 專用加密加速)

Memory Cluster
    LD0   LD1   LD2   LD3      (4x Load pipelines, 2x 128-bit/cycle)
    ST0   ST1   ST2   ST3      (4x Store pipelines, write-combining)
    D-TLB (L0: 64 entry, 1-cyc) (per-thread independent)
```

#### 4.3.2 關鍵延遲參數

| 操作 | 延遲 | 吞吐量 |
|------|------|--------|
| Integer ALU | 1 cycle | 4/cycle |
| Integer MUL (64-bit) | 3 cycles | 1/cycle |
| Integer DIV (64-bit) | 18–30 cycles | 1/20 cycle |
| FP FMA (64-bit) | 4 cycles | 2/cycle |
| FP DIV/SQRT | 10–15 cycles | 1/10 cycle |
| Vector ADD (512-bit) | 2 cycles | 2/cycle |
| Vector FMA (512-bit) | 4 cycles | 2/cycle |
| Vector permute | 3 cycles | 2/cycle |
| Load (L1 hit) | 5 cycles | 4/cycle |
| Load (L2 hit) | 12 cycles | 2/cycle |
| Store (L1) | 3 cycles (addr) + 退休 | 4/cycle |

### 4.4 記憶體子系統

```
L1 I-Cache (64 KB/core, 8-way, 4cy) ──┐
L1 D-Cache (64 KB/core, 8-way, 5cy) ──┼──► L2 Cache (1 MB/core, 16-way, 12cy)
                                         │    HW prefetch: L1D + L2
                                         │    Stride + Stream + Region
                                         │
                                         ▼
                              L3 Cache (64 MB/chiplet, 32-way, 35cy)
                              3D V-Cache 可選: +64 MB
                                         │
                                         ▼
                              Memory Controller
                              DDR5-6400 / HBM3 (AI 版)
```

#### 4.4.1 載入/儲存單元特色

- **Memory Disambiguation**：基於預測的記憶體別名分析，允許非順序載入發射，錯誤時重播
- **Store-to-Load Forwarding**：4-entry store queue，0-cycle forwarding（地址匹配時）
- **Data Prefetcher**：
  - L1: Stride prefetcher（16 streams）
  - L2: Stream + Region prefetcher（64 streams），針對 AI 工作負載優化
- **RVV Gather/Scatter**：硬體支援向量 gather/scatter，降低不規則存取延遲

### 4.5 SMT-4 實作細節

| 資源 | 策略 | 每執行緒配額 |
|------|------|-------------|
| Fetch | 輪詢 (Round-Robin) + 優先權 | 8 inst/cycle max |
| Decode/Rename | 動態分配 | 依 IQ 壓力調整 |
| Issue Queues | 靜態分區 + 動態借用 | 最小 25% 保留 |
| PRF | 完全動態 | 無硬分區，依 ROB 需求 |
| L1 I/D | 路分區 (Way-partitioning) | CAT (Cache Allocation Tech) |
| L2/L3 | 共享 + QoS 標記 | 避免單執行緒佔滿 |
| ROB | 靜態分區 | 256 entries / thread (總 1K) |

**SMT 效能目標**：
- 2-way SMT: +30% throughput（典型伺服器工作負載）
- 4-way SMT: +60% throughput（高平行雲端/容器場景）
- 單執行緒峰值：不折損（關閉 SMT 時全資源可用）

### 4.6 進階特色（ZEN++ 差異化）

#### 4.6.1 AI 協同指令集擴展（ORCA-AIX）

| 擴展 | 功能 | 說明 |
|------|------|------|
| `AIX.SEND` | 發送 tensor 描述子到 AI 引擎 | 零複製，透過共享記憶體語意 |
| `AIX.SYNC` | 同步 CPU-AI 執行 | 輕量級屏障，< 50 cycles |
| `AIX.QUERY` | 查詢 AI 引擎狀態/利用率 | 動態負載平衡 |
| `AIX.PREF` | AI-aware 預取提示 | 根據 AI 模型圖預取權重 |

#### 4.6.2 安全與可靠性

| 功能 | 實作 | 說明 |
|------|------|------|
| MTE (Memory Tagging) | 4-bit tags, 硬體檢查 | 防 use-after-free / buffer overflow |
| PAC (Pointer Auth) | QARMA5 演算法 | 防 ROP/JOP 攻擊 |
| TEE (Trusted Execution) | 雙世界 (Secure/Normal) | 基於 RISC-V PMP/Smepmp + 擴展 |
| RAS (Reliability) | ECC 全覆蓋 (L1/L2/L3/PRF) | SECDED / Chipkill (L3) |
| DVFS | 核心級獨立調頻 | 10ms 反應時間，提升 15% perf/W |

### 4.7 微架構參數總表

| 參數 | v6.3 ZEN++ | AMD Zen 5 | Apple M4 |
|------|-----------|-----------|----------|
| Dispatch Width | 12 | 8 | 12 |
| Retire Width | 16 | 8 | 12 |
| SMT | 4-way | 2-way | 無 |
| ROB | 1,024 | 768 | ~650 |
| INT Scheduler | 64 entries | 48 | ~60 |
| FP Scheduler | 48 entries | 36 | ~40 |
| LS Scheduler | 32 entries | 24 | ~28 |
| INT ALU | 6 | 6 | 6 |
| FP/Vec FMA | 4 (含 2x RVV) | 4 | 4 |
| Load Ports | 4 | 3 | 3 |
| Store Ports | 4 | 2 | 2 |
| L2 / core | 1 MB | 1 MB | 0.75 MB |
| L3 (shared) | 64 MB + 3D V-Cache | 32–64 MB | 0 (SoC 架構) |
| Target Clock | 3.2–3.8 GHz | 4.0–5.5 GHz | 3.5–4.5 GHz |
| Peak INT IPC | ~6.0 | ~5.5 | ~6.5 |
| Peak FP IPC | ~8.0 (w/ RVV) | ~6.0 | ~8.0 |

---

## 5. AI 加速器設計

### 5.1 設計目標

| 項目 | 目標規格 |
|------|---------|
| 峰值算力 (INT8) | 128 TOPS / Tile |
| 峰值算力 (BF16/FP16) | 64 TFLOPS / Tile |
| 峰值算力 (FP32) | 32 TFLOPS / Tile |
| HBM3 容量 | 24 GB / Tile (3 stacks) |
| HBM3 頻寬 | 819 GB/s / Stack |
| 片上 SRAM | 64 MB / Tile |
| 多 Tile 擴展 | 最多 8 Tiles (chiplet) |
| CPU-AI 延遲 | < 50 ns (AIX.SYNC) |
| 功耗 | 150W / Tile (含 HBM3) |

### 5.2 整體架構

```
ORCA v6.3 SoC 頂層架構

CPU Tile 0 (8C SMT-4) ◄──► CPU Tile 1 (8C) ◄──► CPU Tile 2 (8C) ◄──► CPU Tile 3 (8C)
       │                      │                      │                      │
       └──────────────────────┴──────────────────────┴──────────────────────┘
                              │
                    Coherent Mesh (AMBA CHI-E, 2 TB/s bisection)
                    (NoC, 4×4 mesh)
                              │
AI Tile 0 (128 TOPS) ◄──► AI Tile 1 (128 TOPS) ◄──► AI Tile 2 (128 TOPS) ◄──► AI Tile 3 (128 TOPS)
+ HBM3×3                + HBM3×3                + HBM3×3                + HBM3×3

[可選擴展] AI Tile 4–7 (第二個 chiplet 基板，透過 BoW 互連)
```

### 5.3 AI Tile 微架構

```
AI Tile 內部架構 (ORCA-NPU v3)

全域控制與調度單元 (GSCU)
    • 指令解碼與發射 (ORCA-NPU ISA)
    • 任務分派至 16 個計算叢集 (Cluster)
    • 與 CPU 的 AIX 介面處理 (AIX.SEND/SYNC/QUERY/PREF)
    • DMA 引擎：16 通道，支援壓縮/解壓縮 (4:1 稀疏/量化)
                │
    Cluster 0   Cluster 1   Cluster 2  ...   Cluster 15
    (8 TOPS)    (8 TOPS)    (8 TOPS)         (8 TOPS)
        │           │           │                  │
        └───────────┴───────────┴──────────────────┘
                          │
              共享 L2 SRAM (64 MB, 8-bank)
                  權重快取 (Weight Cache): 48 MB
                  Activation 暫存: 16 MB
                  頻寬: 8 TB/s (on-die, 2nm 製程)
                  ECC: SECDED
                          │
              HBM3 記憶體控制器 (3 stacks)
                  每 Stack: 8-Hi, 8 GB, 819 GB/s
                  總容量: 24 GB, 總頻寬: 2.46 TB/s
```

### 5.4 計算叢集（Cluster）微架構

每個 Cluster 包含 4 個計算單元（CU），每個 CU 是一個 2D 脈動陣列（Systolic Array）：

```
Compute Unit (CU) 架構

Input Buffer (64 KB) ◄────► Weight Buffer (256 KB)
    (activations)              (weights)
         │                          │
         ▼                          ▼
    ┌─────────────────────────────────────┐
    │      2D Systolic Array (64×64 PEs) │
    │                                     │
    │    PE  PE  PE  ...   64 rows       │
    │    PE  PE  PE  ...   每 PE: 1x INT8 MAC / cycle
    │    ... ... ... ...   或 1x BF16 FMA / 2 cycles
    │                      或 1x FP32 FMA / 4 cycles
    │                                     │
    │  每 CU 峰值: 4,096 MACs/cycle @ 1 GHz = 8.19 TOPS (INT8)
    │  每 Cluster (4 CU): 32.77 TOPS
    │  每 Tile (16 Cluster): 524 TOPS (理論) → 實際 128 TOPS (利用率 24%)
    └─────────────────────────────────────┘
         │
         ▼
    累加器 / 輸出緩衝區 (Accumulator, 128 KB)
        • 支援 32-bit 累加 (INT32 / FP32)
        • 內建 ReLU/SiLU/GELU/Sigmoid 啟動函數硬體單元
        • 內建 LayerNorm / BatchNorm / RMSNorm 硬體加速
        • 內建 Softmax / Top-K 硬體單元 (用於 Attention)
```

### 5.5 精度支援與吞吐量

| 精度 | 每 PE 吞吐量 | 每 CU (64×64) | 每 Tile (16 Clusters) | 利用率目標 |
|------|-------------|--------------|----------------------|-----------|
| INT8 | 1 MAC/cycle | 8.19 TOPS | 524 TOPS | 24% → 128 TOPS |
| INT4 | 2 MACs/cycle | 16.38 TOPS | 1,048 TOPS | 20% → 210 TOPS |
| BF16 | 0.5 FMA/cycle | 4.10 TFLOPS | 262 TFLOPS | 24% → 64 TFLOPS |
| FP16 | 0.5 FMA/cycle | 4.10 TFLOPS | 262 TFLOPS | 24% → 64 TFLOPS |
| FP32 | 0.25 FMA/cycle | 2.05 TFLOPS | 131 TFLOPS | 24% → 32 TFLOPS |
| FP8 (E4M3/E5M2) | 2 MACs/cycle | 16.38 TOPS | 1,048 TOPS | 20% → 210 TOPS |

### 5.6 資料流架構（三層優化）

1. **Weight-Stationary（WS）在 CU 內**：權重載入後靜態駐留，多個 activation 向量流過
2. **Row-Stationary（RS）在 Cluster 內**：4 個 CU 共享 output tile 不同行，橫向資料廣播
3. **Tile-Stationary（TS）在全 Tile**：16 個 Cluster 分別處理不同 output channel 或 batch

### 5.7 稀疏性與壓縮加速

| 功能 | 實作 | 效能增益 |
|------|------|--------|
| 結構化稀疏 (2:4) | 硬體跳過零權重 PE | 2x 有效吞吐量 |
| 非結構化稀疏 | 壓縮編碼 + 索引解碼 | 1.5–1.8x（依稀疏度） |
| 動態稀疏（Activation） | 零值跳過邏輯 | 1.2–1.5x |
| 量化壓縮 | INT4/FP8 原生支援 | 2x 記憶體頻寬效率 |
| 權重壓縮格式 | 區塊浮點 (Block FP, 8×8 sharing exponent) | 2x 儲存密度，< 1% 精度損失 |

### 5.8 Transformer / LLM 專用硬體

#### 5.8.1 注意力引擎（Attention Engine）

```
專用 Attention 加速單元 (每 Tile 4 個)

Q/K/V Projection (GEMM) ──► Q×K^T (Score) (GEMM) ──► Softmax + Mask (HW unit) ──► ×V (Output) (GEMM)

特色:
• FlashAttention-3 風格分塊計算，減少 HBM 存取
• 支援 GQA (Grouped Query Attention) 與 MQA (Multi-Query)
• 支援 ALiBi / RoPE / Yarn 位置編碼硬體注入
• 支援 KV-Cache 壓縮 (4-bit / 8-bit 量化)
• 序列長度: 最多 128K

效能: 每單元 2 TFLOPS (BF16) → 每 Tile 8 TFLOPS Attention 專用吞吐
```

#### 5.8.2 MoE 路由加速

| 功能 | 實作 | 說明 |
|------|------|------|
| Top-K 路由 | 硬體 Top-K (K=2~8) | 每 cycle 完成 16K expert 分數排序 |
| Conditional Routing | 稀疏啟動標記 | 僅載入被選中的 expert 權重，節省 80% HBM 頻寬 |
| Expert Parallelism | 跨 Tile 分片 | 每個 expert 可映射到不同 Tile，All-to-All 透過 NoC |

### 5.9 記憶體子系統詳細設計

#### 5.9.1 HBM3 配置

| 參數 | 規格 |
|------|------|
| Stack 數量 | 3 stacks / Tile |
| 每 Stack 容量 | 8 GB (8-Hi) |
| 每 Stack 頻寬 | 819 GB/s |
| 總容量 | 24 GB / Tile |
| 總頻寬 | 2.46 TB/s / Tile |
| 介面 | 每 Stack 1024-bit data bus |
| PHY | 3nm 製程，每 pin 6.4 Gbps |
| 功耗 | ~12W / Stack (含 PHY) |

#### 5.9.2 片上 SRAM 階層

| 層級 | 容量 | 頻寬 | 延遲 | 用途 |
|------|------|------|------|------|
| PE 暫存器 | 1 KB / PE | 16 TB/s (陣列內) | 1 cycle | 部分和累加 |
| CU Input Buffer | 64 KB / CU | 512 GB/s | 2 cycles | Activation 暫存 |
| CU Weight Buffer | 256 KB / CU | 512 GB/s | 2 cycles | 權重快取 |
| Cluster L2 | 4 MB / Cluster | 128 GB/s | 5 cycles | 跨 CU 共享 |
| Tile L2 | 64 MB / Tile | 8 TB/s | 10 cycles | 全域權重/activation |

#### 5.9.3 記憶體一致性（與 CPU 協同）

```
CPU L3 Cache ◄──► Coherent Mesh (CHI-E) ◄──► AI Tile L2 SRAM
                      │
                      ├── 一致性協議: MESI-F (Modified/Exclusive/Shared/Invalid/Forward)
                      ├── 快取行大小: 128 byte (對齊 HBM3 burst)
                      ├── 直連存取: CPU 可透過 AIX 指令直接讀寫 AI L2
                      └── 同步機制: AIX.SYNC 觸發全域快取 flush + 屏障
```

### 5.10 AIX 指令集擴展詳細規格

#### 5.10.1 AIX.SEND — 發送 Tensor 描述子

```
編碼: AIX.SEND rd, rs1, rs2
  • rs1: 記憶體位址 (Tensor Descriptor Block, 64 byte)
  • rs2: 目標 AI Tile ID (0–7) + 優先權 (3 bit)
  • rd:  回傳 handle (用於後續 SYNC/QUERY)

Tensor Descriptor Block (64 byte):
  Offset 0–7:   Tensor Base Address (CPU 虛擬位址)
  Offset 8–15:  Tensor Dimensions (4× 32-bit: N,C,H,W)
  Offset 16:    Data Type (INT8/BF16/FP32/etc.)
  Offset 17:    Layout (NCHW/NHWC/Blocked)
  Offset 18:    Sparsity Mask Address (可選)
  Offset 19:    Compression Format (None/2:4/BlockFP)
  Offset 20–23: Destination in AI L2 SRAM (tile offset)
  Offset 24–31: Reserved
  Offset 32–63: User-defined Metadata (模型層 ID 等)

延遲: 10–20 cycles (解析描述子 + 啟動 DMA)
副作用: 非同步，不阻塞 CPU
```

#### 5.10.2 AIX.SYNC — 同步屏障

```
編碼: AIX.SYNC rd, rs1
  • rs1: handle (來自 AIX.SEND)
  • rd:  狀態碼 (0=完成, 1=逾時, 2=錯誤)

行為:
  1. CPU 發出 SYNC 後，可選擇:
     a. 阻塞等待 (rd 輪詢直到完成)
     b. 非阻塞 (rd 立即回傳，透過中斷通知)
  2. AI Tile 完成計算後:
     a. 將結果寫回指定記憶體位址
     b. 發送完成中斷至 CPU (每 Tile 獨立 IRQ)
  3. 隱含快取同步: AI Tile 的 L2 write-back 至 CPU L3

延遲: < 50 ns (最佳情況，無資料搬移)
      < 200 ns (含 L2 flush 至 HBM3)
```

#### 5.10.3 AIX.QUERY — 狀態查詢

```
編碼: AIX.QUERY rd, rs1
  • rs1: handle 或 Tile ID
  • rd:  64-bit 狀態向量

rd 回傳格式:
  Bit 0–15:   完成進度 % (0–10000, 固定點)
  Bit 16–23:  Tile 溫度 (°C)
  Bit 24–31:  Tile 功耗 (W, 固定點)
  Bit 32–39:  HBM3 頻寬利用率 %
  Bit 40–47:  CU 利用率 % (平均)
  Bit 48–55:  佇列深度 (待處理任務數)
  Bit 56:     錯誤標記 (ECC/溫度/逾時)
  Bit 57–63:  保留

用途: 動態負載平衡、熱管理、效能分析 (perf)
```

#### 5.10.4 AIX.PREF — AI-aware 預取

```
編碼: AIX.PREF rs1, rs2
  • rs1: 預取位址 (權重或 activation)
  • rs2: 預取類型 (0=權重, 1=activation, 2=KV-cache)

行為:
  • 提示 AI Tile 的 DMA 引擎提前將資料從 HBM3 搬至 L2 SRAM
  • 不阻塞 CPU，純提示性 (hint)
  • AI 硬體根據內部排程決定是否執行

用途: 在 CPU 準備下一層 tensor 描述子時，重疊資料搬移
```

### 5.11 多 Tile 擴展與 Chiplet 互連

#### 5.11.1 單基板（4 Tile）配置

```
ORCA v6.3 基板（Organic Substrate）

AI Tile 0 (+ HBM3×3) ◄──► AI Tile 1 (+ HBM3×3) ◄──► AI Tile 2 (+ HBM3×3) ◄──► AI Tile 3 (+ HBM3×3)
       │                       │                       │                       │
       └───────────────────────┴───────────────────────┴───────────────────────┘
                              │
                        基板 NoC (2 TB/s, 延遲 < 5 ns)
                        (AMBA CHI)
                              │
CPU Tile 0 (8C) ◄──► CPU Tile 1 (8C) ◄──► CPU Tile 2 (8C) ◄──► CPU Tile 3 (8C)

總算力: 512 TOPS INT8 (4 AI Tiles)
總容量: 96 GB HBM3
總功耗: ~600W (CPU 200W + AI 400W)
```

#### 5.11.2 多基板擴展（BoW 互連）

```
基板 0 (主) ◄────BoW Link────► 基板 1 (擴展)
   │                              │
   ├── 4× AI Tile                 ├── 4× AI Tile
   ├── 4× CPU Tile                ├── 4× CPU Tile (或純 AI)
   └── 基板 NoC                  └── 基板 NoC
          │                            │
          └──────┬─────────────────────┘
                 │
           BoW Router (8 條 link, 每條 128 GB/s)
           (封包交換)

BoW 規格:
  • 頻寬: 128 GB/s / link (單向), 總 1 TB/s (8 link)
  • 延遲: < 2 ns (PHY) + < 3 ns (router) = < 5 ns
  • 功耗: < 0.5 pJ/bit
  • 距離: 最多 2 mm (基板對基板)
  • 拓撲: 2D Torus 或 Fat Tree
```

### 5.12 軟體棧介面

| 層級 | 介面 | 說明 |
|------|------|------|
| Framework | PyTorch 2.x / JAX / TensorFlow | 原生支援，透過 torch.compile() |
| Graph Compiler | ORCA-MLIR | 基於 MLIR，自動圖優化、量化、分片 |
| Runtime | ORCA-RT | 任務排程、記憶體管理、多 Tile 負載平衡 |
| Kernel Lib | ORCA-BLAS / ORCA-Transformer | 手寫優化 kernel，覆蓋 90% 模型運算 |
| Driver | Linux Kernel Module | AIX 指令封裝、中斷處理、熱插拔 |
| Firmware | ORCA-FW | Tile 初始化、ECC 校正、溫度/功耗監控 |

### 5.13 功耗與面積估算（3nm 製程）

| 項目 | 面積 (mm²) | 功耗 (W) | 說明 |
|------|-----------|---------|------|
| 16 Clusters (含 CU) | 180 | 95 | 主要計算面積 |
| Attention Engine ×4 | 24 | 18 | 專用硬體 |
| L2 SRAM (64 MB) | 45 | 12 | SRAM 面積主導 |
| HBM3 PHY ×3 | 18 | 15 | PHY + 控制器 |
| NoC / GSCU / DMA | 15 | 8 | 互連與控制 |
| 其他 (ECC, 測試) | 8 | 2 | |
| **總計 (AI Tile)** | **~290 mm²** | **150W** | |
| **CPU Tile (8C)** | ~120 mm² | 50W | |
| **基板 (4+4 Tile)** | ~1,640 mm² | 600W | 含互連與 I/O |

### 5.14 與競品對比

| 規格 | ORCA v6.3 (4 Tile) | NVIDIA H100 SXM | Google TPU v5e | AMD MI300X |
|------|-------------------|-----------------|----------------|------------|
| INT8 TOPS | 512 | 3,958 | 197 | 1,300 |
| BF16 TFLOPS | 256 | 1,979 | 98 | 1,300 |
| HBM 容量 | 96 GB | 80 GB | 16 GB | 192 GB |
| HBM 頻寬 | 9.8 TB/s | 3.35 TB/s | 819 GB/s | 5.3 TB/s |
| 功耗 | 600W | 700W | 200W | 750W |
| CPU 整合 | ✅ 同封裝 | ❌ 外接 | ❌ 外接 | ❌ 外接 |
| 延遲 (CPU→AI) | < 50 ns | ~1 µs (PCIe) | ~5 µs (網路) | ~1 µs |
| 製程 | 3nm | 4nm | 5nm | 5nm |
| 價格定位 | 中端 AI 伺服器 | 高端 $30K+ | 雲端租賃 | 高端 $20K+ |

**ORCA v6.3 差異化優勢**：
1. 超低延遲 CPU-AI 協同（< 50 ns）
2. 高頻寬記憶體（9.8 TB/s，超越 H100 3 倍）
3. 同封裝整合（CPU + AI 共享記憶體語意，無需資料複製）
4. RISC-V 開放生態（無授權費，可客製化 AIX 指令）

---

## 6. RTL 架構規格與 Stub

### 6.1 專案檔案結構

```
orca_v63/
├── rtl/
│   ├── common/                    # 共享基礎模組
│   │   ├── orca_pkg.sv          # 全域參數與型別定義
│   │   ├── orca_axi_pkg.sv      # AMBA AXI/CHI 介面型別
│   │   ├── orca_aix_pkg.sv      # AIX 指令擴展介面型別
│   │   └── primitives/          # 標準單元 wrapper
│   │       ├── sram_1r1w.sv
│   │       ├── sram_2r1w.sv
│   │       ├── flop_array.sv
│   │       └── clock_gate.sv
│   │
│   ├── soc/                       # 頂層 SoC
│   │   └── orca_v63_soc.sv
│   │
│   ├── cpu/                       # CPU Tile (ZEN++)
│   │   ├── orca_v63_cpu_tile.sv
│   │   ├── frontend/
│   │   │   ├── ifu_bpu.sv
│   │   │   ├── ifu_fetch.sv
│   │   │   ├── ifu_btb.sv
│   │   │   └── ifu_tlb.sv
│   │   ├── decode/
│   │   │   ├── idu_decoder.sv
│   │   │   ├── idu_uop_queue.sv
│   │   │   └── idu_rvc_expand.sv
│   │   ├── rename/
│   │   │   ├── rnu_rat.sv
│   │   │   ├── rnu_freelist.sv
│   │   │   └── rnu_remap.sv
│   │   ├── scheduler/
│   │   │   ├── isu_int.sv
│   │   │   ├── isu_fp.sv
│   │   │   ├── isu_mem.sv
│   │   │   └── isu_wake.sv
│   │   ├── execution/
│   │   │   ├── exu_alu.sv
│   │   │   ├── exu_mul.sv
│   │   │   ├── exu_fpu.sv
│   │   │   ├── exu_vec.sv
│   │   │   ├── exu_bru.sv
│   │   │   └── exu_crypto.sv
│   │   ├── memory/
│   │   │   ├── lsu_ld.sv
│   │   │   ├── lsu_st.sv
│   │   │   ├── lsu_dtlb.sv
│   │   │   ├── lsu_mshr.sv
│   │   │   └── lsu_dcache.sv
│   │   ├── cache/
│   │   │   ├── icache.sv
│   │   │   ├── icache_tag.sv
│   │   │   ├── dcache.sv
│   │   │   ├── dcache_tag.sv
│   │   │   ├── l2cache.sv
│   │   │   └── l3cache.sv
│   │   └── commit/
│   │       ├── cmt_rob.sv
│   │       ├── cmt_archreg.sv
│   │       └── cmt_trap.sv
│   │
│   ├── ai/                        # AI Tile (ORCA-NPU v3)
│   │   ├── orca_v63_ai_tile.sv
│   │   ├── ctrl/
│   │   │   ├── npu_gscu.sv
│   │   │   ├── npu_dma.sv
│   │   │   └── npu_aix_intf.sv
│   │   ├── cluster/
│   │   │   ├── npu_cluster.sv
│   │   │   └── npu_cu.sv
│   │   ├── pe/
│   │   │   ├── npu_systolic.sv
│   │   │   ├── npu_pe.sv
│   │   │   └── npu_acc.sv
│   │   ├── attention/
│   │   │   └── npu_attn_engine.sv
│   │   ├── memory/
│   │   │   ├── npu_l2_sram.sv
│   │   │   ├── npu_hbm3_ctrl.sv
│   │   │   └── npu_hbm3_phy.sv
│   │   └── noc/
│   │       └── npu_tile_noc.sv
│   │
│   ├── noc/                       # 片間/基板互連
│   │   ├── orca_noc_router.sv
│   │   ├── orca_noc_link.sv
│   │   ├── orca_chi_coh.sv
│   │   └── orca_bow_link.sv
│   │
│   └── pad/                       # IO / PHY
│       ├── ddr5_ctrl.sv
│       ├── pcie_gen6.sv
│       └── gpio_pad.sv
│
├── tb/                            # Testbench
│   ├── orca_v63_soc_tb.sv
│   ├── cpu_tile_tb/
│   └── ai_tile_tb/
│
├── syn/                           # 綜合約束
│   ├── orca_v63_soc.sdc
│   ├── cpu_tile.tcl
│   └── ai_tile.tcl
│
└── docs/
    └── arch_spec_v63.md
```

### 6.2 關鍵參數定義（orca_pkg.sv 摘要）

| 參數類別 | 參數名 | 值 | 說明 |
|---------|--------|-----|------|
| SoC | NUM_CPU_TILES | 4 | 4 CPU tiles |
| SoC | NUM_AI_TILES | 4 | 4 AI tiles |
| SoC | CORES_PER_CPU_TILE | 8 | 8 cores per tile |
| SoC | SMT_THREADS | 4 | 4-way SMT |
| CPU | FETCH_WIDTH | 8 | 8 inst per block |
| CPU | DECODE_WIDTH | 6 | 6-wide decoder |
| CPU | DISPATCH_WIDTH | 12 | 12-wide dispatch |
| CPU | RETIRE_WIDTH | 16 | 16-wide retire |
| CPU | ROB_ENTRIES | 1024 | 1K-entry ROB |
| CPU | INT_PRF_ENTRIES | 384 | Integer PRF |
| CPU | FP_PRF_ENTRIES | 256 | FP PRF |
| CPU | VEC_PRF_ENTRIES | 512 | Vector PRF (512-bit) |
| CPU | INT_SCHED_DEPTH | 64 | Integer scheduler |
| CPU | FP_SCHED_DEPTH | 48 | FP scheduler |
| CPU | MEM_SCHED_DEPTH | 32 | Memory scheduler |
| CPU | NUM_INT_ALU | 4 | 4x ALU |
| CPU | NUM_FP_FMA | 2 | 2x FMA |
| CPU | NUM_VEC_ALU | 2 | 2x vector ALU |
| CPU | NUM_LD_PIPE | 4 | 4x load |
| CPU | NUM_ST_PIPE | 4 | 4x store |
| CPU | L1I_SIZE_KB | 64 | L1 I-Cache |
| CPU | L1D_SIZE_KB | 64 | L1 D-Cache |
| CPU | L2_SIZE_KB | 1024 | L2 (1 MB) |
| CPU | L3_SIZE_MB | 64 | L3 shared |
| AI | AI_TILES | 4 | 4 AI tiles |
| AI | CLUSTERS_PER_TILE | 16 | 16 clusters |
| AI | CUS_PER_CLUSTER | 4 | 4 CU per cluster |
| AI | PE_ARRAY_DIM | 64 | 64×64 systolic |
| AI | AI_L2_SIZE_MB | 64 | 64 MB L2 SRAM |
| AI | HBM3_STACKS | 3 | 3 stacks per tile |
| NoC | NOC_DATA_WIDTH | 512 | 512-bit flit |
| NoC | NOC_VC | 4 | 4 virtual channels |
| AIX | AIX_HANDLE_BITS | 16 | 16-bit handle |
| AIX | AIX_TILEID_BITS | 3 | 3-bit tile ID (0–7) |
| AIX | AIX_TDB_SIZE | 512 | 64 bytes descriptor |
| ISA | XLEN | 64 | 64-bit RISC-V |
| ISA | VLEN | 512 | 512-bit RVV |

### 6.3 頂層 SoC 介面摘要

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
|------|------|------|--------|---------|--------|
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
|------|------|--------|
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
|------|------|---------|--------|
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
|------|------|------|--------|
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
