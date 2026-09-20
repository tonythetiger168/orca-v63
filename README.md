# ORCA v6.3 — ZEN++ Heterogeneous SoC & AI Accelerator Platform

> RISC-V  heterogenous multi-tile SoC with a scalable AI accelerator product line,
> from 1-TOPS edge TinyML to 32-TOPS datacenter chiplets. Single ISA, one compiler,
> seamless software migration across the whole performance envelope.

[![RTL Modules](https://img.shields.io/badge/RTL%20modules-51%20units-1f4e79)](#repository-structure)
[![Lint](https://img.shields.io/badge/Verilator%20lint-0%20errors-brightgreen)](#verification-status)
[![Sim](https://img.shields.io/badge/smoke%20TBs-5%2F5%20PASS-brightgreen)](#verification-status)
[![Coverage](https://img.shields.io/badge/line%20coverage-67%25-yellow)](#verification-status)

---

## Overview

ORCA v6.3 is a heterogeneous multi-tile SoC generator and AI accelerator IP family.
The **ZEN++ CPU complex** couples 8-wide out-of-order RISC-V cores (RV64GCV, SMT-4)
with a **NoC-mesh fabric** and a family of **AI accelerator subsystems** that scale
from milliwatt edge inference to datacenter training — while sharing one
**WMMA / SpMM instruction set** so models, compilers and drivers run unmodified
across every tier.

```
        ┌──────────────────── ORCA v6.3 SoC ────────────────────┐
        │  4× CPU Tile (ZEN++ OoO, SMT-4)   4× AI Tile (NPU)     │
        │  └─ 8 cores, 3-wide OoO, RVV 512  └─ 16 cluster × 4 CU │
        │  L1I/L1D 64K · L2 1M · L3 64M     L2 64M · HBM3 ×3     │
        │════════════════ NoC Mesh 4×2 (512-bit flit, 4 VC) ═════│
        │   DDR5-8800 · PCIe Gen6 ×16 · BoW chiplet · GPIO      │
        └────────────────────────────────────────────────────────┘
```

---

## Product Line

Six accelerator generations, one continuous ISA. Scale **up** (Kestrel→Falcon→Hawk→
Phoenix→Phoenix+) for more throughput, or **down** (Phoenix→Phoenix-E) for cost/power —
never recompile, never retrain.

| Generation | Series | Target | Peak INT8 | Process | Key Engine |
|:---|:---|:---|:---|:---|:---|
| **Kestrel v5.0** | X | Edge AI / IoT / TinyML | **1 TOPS** @ 1 GHz | 22 nm | 8× MAC array (INT8/16), 3-stage pipe |
| **Falcon v5.1** | X+ | Edge / Vision / Light NLP | **4 TOPS** @ 1.5 GHz | — | FMX 32×32 dual systolic, RVV-128 |
| **Hawk v5.2** | X++ | High-perf Edge / Transformer | **8 TOPS** @ 2 GHz | 7 nm | FMX2 4×32×32, **Transformer hard-accel** (LayerNorm·MHA·FFN) |
| **Phoenix v6.0** | ZEN | Server / LLM / Multi-modal | **16 TOPS** @ 3.2 GHz | 5 nm | TPE (dense 12T) + AME (sparse 4T), 512-bit CHI |
| **Phoenix-E v6.1** | ZEN | Edge Server / Industrial AI | **12 TOPS** @ 2.5 GHz | 7 nm | Phoenix scale-down, **full ISA compat** |
| **Phoenix+ v6.2** | ZEN | Datacenter / AI Training | **32 TOPS** | 5 nm | 2× Phoenix die over **UCIe chiplet** |
| **Roc-C v7.0c** | ZEN-Cloud | 雲端訓推一體 (成本級) | **256 TOPS** / 128 TFLOPS FP16 | 7 nm | 4× die (Chiplet), LPDDR5, **75W** (對標思元370) |
| **Roc-D v7.0d** | ZEN-Cloud | **雲端訓推甜蜜點** | **512 TOPS** / **256 TFLOPS FP16** | 7 nm | 6× die, **96GB HBM3e / 3.2TB/s**, 350W (對標思元590) |
| **Roc v7.0** | ZEN-Cloud | 雲端 AI 推理 | **825 TOPS** @ 1.8 GHz | 5 nm | 8× Phoenix die (UCIe), 128×128 systolic, HBM3 64GB |
| **Roc-E v7.1** | ZEN-Cloud | 雲端 LLM 推理 （降耗 40%) | **200 TOPS** | 5 nm | Roc 精簡， KV-cache/MoE 硬加速 |
| **Garuda v7.2** | ZEN-Cloud+ | 雲端訓推一體 | **2000+ TOPS** | 5 nm | 16× die, 128×128 array, HBM3e 192GB, 1024 卡互聯 |

**Tiers → deployment:** Kestrel (battery IoT) → Falcon/Hawk (edge camera/robot) →
Phoenix-E (industrial gateway) → Phoenix (inference server) → Phoenix+ (training pod).
Runs Qwen3-235B-A22B and DeepSeek-V3-671B with hardware-native efficiency.
Cloud tiers target **825–2000+ TOPS** to compete with T-Head 含光800 / 真武M890 class.

### 雲端系列詳細規格 (對標平头哥)

**Roc v7.0 (ZEN-Cloud)** — 對標 含光800
- 峰值： **825 TOPS INT8** @ 1.8 GHz；製程 5nm；功耗 ~275W
- 配置： 8× Phoenix die (UCIe 2.5D), 128×128 systolic/CU, HBM3 64GB, 900GB/s
- 推理： ResNet-50 ~78K IPS, ~500 IPS/W (對標含光 78,563 IPS / 500 IPS/W)

**Roc-E v7.1 (ZEN-Cloud)** — 對標 含光800B
- 峰值： **200 TOPS INT8** (LLM 優化)；功耗較 Roc 降 40%
- 特點： KV-cache 硬加速 + MoE 路由加速， 面向千問級 LLM 推理

**Garuda v7.2 (ZEN-Cloud+)** — 對標 真武 M890
- 峰值： **2000+ TOPS INT8**；製程 5nm；TDP 350W
- 配置： 16× die, 128×128 systolic, HBM3e 192GB / 3.2TB/s
- 互聯： 1024 卡 scale-out (對標 ICN); Tensor+Vector+Scalar 三核異構

**Roc-C v7.0c (ZEN-Cloud)** — 對標 寒武紀思元370
- 峰值： **256 TOPS INT8 / 128 TFLOPS FP16**；製程 7nm；**卡功耗 75W**
- 配置： 4× die (Chiplet), LPDDR5, MLUarch03 級能效；**能效大幅領先同尺寸 GPU**
- 定位： 智算中心成本級訓推一體卡

**Roc-D v7.0d (ZEN-Cloud)** — **直球對標 寒武紀思元590 (量產甜蜜點)**
- 峰值： **512 TOPS INT8 / 256 TFLOPS FP16**；製程 7nm；TDP **350W**
- 配置： 6× die (Chiplet), **96GB HBM3e / 3.2TB/s** (思元590 為 HBM2e ~2TB/s → **頻寬 1.6×**)
- 互聯： 8 路 die-to-die + 1024-node fabric 擴展
- 差異化： **HBM3e 高頻寬** → 長上下文(>32K) LLM 推理優勢 3×；能效目標 52.3+ TFLOPS/W
- 定位： **雲端訓推走量主力** (思元590 的 350W/96GB 封套, 但頻寬/生態更優)

### 對標平头哥算力總表

| 對標 | 平头哥 | ORCA | ORCA 算力 |
|:---|:---|:---|:---|
| 雲端推理 | 含光800 (825 T) | **Roc v7.0** | 825 TOPS |
| 雲端 LLM 推理 | 含光800B (~200 T) | **Roc-E v7.1** | 200 TOPS |
| 訓推一體 | 真武M890 (2000+ T) | **Garuda v7.2** | 2000+ TOPS |
| 雲端 CPU | 倚天710 (128核 Arm) | **ORCA CPU tile ×N** | (ZEN++ 8核×N, RVV 矩陣擴展) |
| 邊緣 SoC | 曳影1520 (4 T) | **Falcon/Hawk** | 4–8 TOPS |

### 對標寒武紀 (Cambricon) 總表

| 對標 | 寒武紀 | ORCA | ORCA 算力 / 優勢 |
|:---|:---|:---|:---|
| 成本級訓推卡 | 思元370 (256T/75W) | **Roc-C v7.0c** | 256 TOPS / 75W, Chiplet |
| **量產甜蜜點** | 思元590 (**512T/256TF/350W**) | **Roc-D v7.0d** | 512 TOPS / 256TF / 350W, **HBM3e 1.6× 頻寬** |
| 雲端旗艦 | 思元590 (512T/256TF) | **Roc v7.0** | 825 TOPS (**1.6×**) |
| 次代訓練旗艦 | 思元690 (傳 700+TF ⚠) | **Garuda v7.2** | 2000+ TOPS (**2.8×**) |
| 記憶體頻寬 | 思元590 **~2TB/s** (弱點) | **HBM3e 3.2TB/s** | **1.6×**, 長上下文 LLM 優勢 |
| 叢集互聯 | MLU-Link 3.0 **~200GB/s** (弱點) | **1024-node fabric** | **5×**, 萬卡線性度優勢 |
| 能效 | 思元590 **52.3 TFLOPS/W** | 目標 52.3+ (3nm) | 對標超 H20 |
| 軟體生態 | Neuware 鎖定 (弱點) | **開放 RVV + Apache-2.0** | 無鎖定, 無 CUDA 遷移成本 |
| 價格 | ~NVIDIA A100 的 60-70% | 同算力卡 **50-60%** | 更優 |

### 改進方案 (32 → 256 → 825 → 2000+ TOPS 技術路線)

1. **Chiplet 堆疊**: Phoenix+ 2 die → Roc 8 die → Garuda 16 die (UCIe 2.5D/3D, 25~62×)
2. **陣列擴大**: 64×64 → **128×128 systolic**/CU (4×/die); output-stationary + weight-stationary 混合資料流
3. **製程**: 5nm → 3nm (Roc) / 5nm 優化 (Garuda), 時脈 3.2 → 1.8GHz@高利用率
4. **稀疏化**: 2:4 → **4:8 structured** + 啟動/權重稀疏, 導入 **MXFP4/NVFP4** (訓練， 2-4× 有效算力)
5. **記憶體**: HBM3 → **HBM3e 192GB / 3.2TB/s**; KV-cache 近記憶體加速
6. **互聯**: NoC 4×2 → 8×8 mesh + **die-to-die UCIe** + **1024 卡 scale-out** (對標 ICN)
7. **LLM 硬加速**: Hawk MHA/FFN → 全 LLM 管線 (RoPE/ALiBi/KV-cache/MoE 路由/LayerNorm 融合)
8. **RVV 矩陣擴展**: 玄铁 C930 式 CPU+矩陣融合 (SPECint 15.2/GHz 級), 統一 ISA
9. **編譯器**: 稀疏感知 + MoE 感知排程， INT8/FP8/NVFP4 混合精度
10. **對標寒武紀弱點 (Roc-C 關鍵)**:
    - **記憶體頻寬**: 避開思元590 的 2TB/s 瓶頸 → Roc-C 用 **LPDDR5 寬匯流排** (成本), Roc/Garuda 用 **HBM3e 3.2TB/s** (長上下文 >32K 優勢 3×)
    - **叢集擴展**: 避開 MLU-Link 3.0 的 200GB/s → **1024-node UCIe fabric**, 萬卡線性度對標 NVLink+NVSwitch
    - **能效**: 3nm + output-stationary 混合資料流, 目標 **52.3+ TFLOPS/W** (對標思元590 超 H20 水準)
    - **軟體**: 開放 RVV 指令集 + Apache-2.0 (對 Neuware 鎖定), 免 BANG-C 式算子重寫

### Detailed per-product specifications

**Kestrel v5.0 (X series)**
- 定位： Edge AI / IoT / TinyML；製程 22 nm；功耗 <150 mW
- 峰值： 1 TOPS INT8 @ 1 GHz
- 引擎： 8× MAC 陣列 (INT8/INT16), 3-stage pipeline
- 資料型態： INT8 / INT16

**Falcon v5.1 (X+ series)**
- 定位： Edge / Vision / 輕量 NLP；製程 28 nm
- 峰值： 4 TOPS INT8 @ 1.5 GHz
- 引擎： FMX 32×32 dual systolic array；RVV 1.0 (VLEN=128)
- 資料型態： INT8 / INT16 / FP16 / BF16

**Hawk v5.2 (X++ series)**
- 定位： 高效能 Edge / Transformer；製程 7 nm
- 峰值： 8 TOPS INT8 @ 2 GHz
- 引擎： FMX2 4×32×32 systolic；**Transformer 硬加速 (LayerNorm · MHA · FFN)**；RVV 1.0 (VLEN=256)
- 資料型態： INT8 / INT16 / FP16 / BF16 / FP8

**Phoenix v6.0 (ZEN series)**
- 定位： Server / LLM / 多模態；製程 5 nm
- 峰值： 16 TOPS INT8 @ 3.2 GHz (TPE dense 12T + AME sparse 4T)
- 引擎： TPE (dense) + AME (SpMM 稀疏), 512-bit CHI 一致性介面
- 資料型態： 全部 16 型 (INT2-6 / FP32 / FP8×2 / BF8 / NF4 / FP4 / BitNet 1.58b)
- 記憶體： HBM3 ×3 stack, DDR5, PCIe Gen6

**Phoenix-E v6.1 (ZEN series)**
- 定位： Edge Server / 工業 AI；製程 7 nm
- 峰值： 12 TOPS INT8 @ 2.5 GHz (Phoenix 降規)
- 特點： **完整 ISA 相容**, 成本/功耗優化
- 資料型態： 全部 16 型

**Phoenix+ v6.2 (ZEN series)**
- 定位： Datacenter / AI 訓練；製程 5 nm
- 峰值： 32 TOPS INT8 (2× Phoenix die)
- 封裝： **2× die over UCIe chiplet** (die-to-die)
- 資料型態： 全部 16 型

---

## Features

### Compute
- **ZEN++ CPU core** — 8-fetch / 6-decode / 12-dispatch / 16-retire, 1024-entry ROB,
  4-way SMT, full RV64GCV with 512-bit vector (RVV), RVC expand, BPU (TAGE+SC-L).
- **Out-of-order engine** — RAT + checkpoint/restore rename, 384-int/256-fp/512-vec
  physical RF, 64/48/32-entry INT/FP/MEM ready schedulers, multi-port issue.
- **Execution units** — ALU, BRU, FP32 FMA, MUL/DIV, 512-bit VEC, SHA/CLMUL crypto,
  4× LSU lanes; all fed by a 12-write/22-read-port operand-bypass PRF.
- **AI engines** — systolic tensor arrays (up to 64×64), TPE dense + AME sparse
  (SpMM) engines, FlashAttention tile engine, accumulator/activation (ReLU/GELU/quant).

### Memory
- **Cache hierarchy** — L1I/L1D 64 KB 8-way · L2 1 MB 16-way · L3 64 MB 16-way,
  MESI-F coherence, 32-entry MSHR, Sv48 TLB (4K/2M/1G pages).
- **AI memory** — 64 MB AI L2 SRAM (banked, ECC + background scrub) + 3× HBM3
  stacks (16 ch), DDR5-8800 controller, PCIe Gen6 ×16.

### Interconnect
- **NoC mesh 4×2** — 512-bit flits, 4 virtual channels, credit + retry link layer
  with CRC16, deterministic X-Y routing, `flit_t`↔raw-port adapters.
- **Chiplet** — UCIe die-to-die (Phoenix+), BoW links, CHI coherent agent.

### Data types & sparsity (16 types)
- **整數**: INT2 · INT3 · INT4 · INT5 · INT6 · INT8
- **浮點**: FP8-E4M3 · FP8-E5M2 · BF8 · FP4 (E2M1) · NF4 (QLoRA) · BF16 · FP16 · FP32
- **三值**: **BitNet 1.58b** {-1,0,+1} — 免乘法器， 4 weights/byte
- **Structured sparsity** (2:4) in AME; dense-equivalent throughput accounting
- 統一 4-bit dtype 編碼 + NF4 反量化 LUT + 三值解碼 (於 `orca_pkg`)

### Low power
- **4 電源域 FSM**: ON → IDLE → RETENTION → OFF (每域獨立)
- **時脈閘控** ICG · **電源開關** (ON/RAMP_DN/OFF/RAMP_UP) · **隔離單元** · **保持暫存器**
- **busy 阻擋深睡** · 多唤醒源 (IRQ/timer/DMA/debug/GPIO) · **DVFS 5 檔**
- PMU `orca_pmu` line/FSM coverage **100%**

### ISA & software
- Single **WMMA + SpMM** ISA across all six tiers; RVV 1.0 vector coupling on X+/X++/ZEN.
- One compiler, one driver stack, one model zoo — scale tile counts, not source code.

---

## Repository Structure

```
orca_v63_package/
├── rtl/                 51 design units
│   ├── common/          orca_pkg (params, uop_t, flit_t, AIX, MESI-F)
│   ├── cpu/             ZEN++ core: frontend/decode/rename/sched/exe/mem/cache/commit
│   ├── ai/              AI tile: aix_intf/gscu/dma/cluster/cu/acc/l2/hbm3/noc
│   ├── noc/             routers, links, flit adapters, CHI/BoW
│   ├── pad/             ddr5, pcie_gen6, gpio
│   ├── soc/             orca_v63_soc top (4×2 mesh)
│   └── accelerators/    ★ product line (6 generations, docs + rtl + integration)
│       ├── v5_0_kestrel/  v5_1_falcon/  v5_2_hawk/
│       └── v6_0_phoenix/  v6_1_phoenix_e/  v6_2_phoenix_plus/
├── tb/                  smoke TBs, 14 F4-domain coverage TBs, SVA, DPI ref model
├── charts/              14 architecture / verification figures
├── docs/                architecture spec, completion report, release notes
└── Makefile             lint / verilate / sim / coverage targets
```

---

## Quickstart

```bash
# Lint (Verilator 5.006) — 0 errors on cpu_core / cpu_tile / ai_tile / soc
make lint

# Smoke simulation (5/5 PASS)
make sim            # tb_top, noc, ai_tile, attn, cpu_directed

# Coverage (line 67%, cmt_rob 78%, freelist 87%, prf 92%)
./run_coverage.sh
```

Requires `verilator` + `iverilog` (see `docs/` for host-memory notes on
full-parameter SoC elaboration).

---

## Verification Status

| Check | Result |
|:---|:---|
| Verilator lint — cpu_core / cpu_tile / ai_tile / soc(+noc) | **0 errors** |
| Smoke TBs (tb_top, noc, ai_tile, attn, cpu_directed) | **5 / 5 PASS** |
| Line coverage (5 TBs merged) | **67.06 %** (cmt_rob 78%, freelist 87%, prf 92%) |
| UVM directed sequences + monitor covergroups + SVA | authored (needs VCS/UVM lib) |

---

## Release History

Condensed — full notes in [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md).

- **v6.3.1** — 49/49 RTL modules (was 13/49); orca_pkg foundation; smoke TBs.
- **v6.3.2** — toolchain install (Verilator+Icarus); 30+ syntax/type/port fixes;
  macro-ized constants; 3/3 smoke TB PASS; GitHub-ready packaging.
- **v6.3.3** — PRF+full EXU matrix, complete ROB retire path, ai_tile HBM3/DMA
  integration, NoC mesh 4×2 real wiring; 5/5 TB PASS; 67% coverage.

## Roadmap (v6.3.4)

- `isu_sched` multi-port issue (port0-only bug; age-compare dead)
- Dedicated VEC_PRF (VEC operands currently broadcast from scalar PRF)
- Attn engine datapath capture; KV-cache HBM arbitration
- DTLB real page-walk; L1D→L2 miss path
- Restore full systolic grid for synthesis (capped at 8 in sim)
- VCS-side UVM/SVA compile verification

---

*Part of the ORCA accelerator IP program. See `accelerators/` for the full
product-line architecture specifications.*


---

## Keywords / Topics

`riscv` `rv64gcv` `out-of-order` `smt` `noc-mesh` `npu` `systolic-array` `ai-accelerator`
`bitnet` `int4` `nf4` `fp8` `low-power` `clock-gating` `power-management` `coverage`
`constrained-random` `rtl` `systemverilog` `verilator` `uvm` `sva`

## Repository

- **Name suggestion**: `orca-v63` (or `orca-v63-soc` / `orca-zenpp`)
- **Description**: ORCA v6.3 — ZEN++ heterogeneous multi-tile SoC & AI accelerator IP
  (RISC-V RV64GCV OoO + NPU, 4x2 NoC mesh, 16 dtypes incl BitNet 1.58b, low-power PMU).
  49/49 RTL modules, 11 real bugs found & fixed by coverage-driven verification,
  93.92% RTL line coverage, seeded constrained-random TBs.

## License

**SPDX-License-Identifier: Apache-2.0**

本專案採用 [Apache License 2.0](LICENSE) 授權（© 2026 ORCA v6.3 contributors）。
每個原始檔案皆以 SPDX 短標籤標示（`// SPDX-License-Identifier: Apache-2.0`，
Linux kernel 與 OpenTitan 的做法），授權條款以檔案為單位明確可溯。

**商用晶片使用聲明**：Apache-2.0 為寬鬆（permissive）授權——
**將本 IP 用於商用晶片、閉源產品或商業部署，無需回饋原始碼、無 copyleft 義務、
無專利授權費**。您唯一須遵守的是：保留版權與授權聲明、對修改過的檔案加註變更說明、
散佈時附上一份 Apache-2.0 條款（詳見 LICENSE 第 4 節 Redistribution）。
