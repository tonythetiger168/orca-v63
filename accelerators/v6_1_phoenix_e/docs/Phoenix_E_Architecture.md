# ORCA v6.1 ZEN — Phoenix-E AI Subsystem Architecture Specification
**Version**: 1.0  **Date**: 2026-09-05  **Target**: Edge Server / High-End IPC / Industrial AI Gateway
---

## 1. Overview
Phoenix-E is the **edge server optimized** variant of the flagship Phoenix AI subsystem. It delivers **12 TOPS** peak INT8 performance at 2.5 GHz on a 7 nm process by downscaling Phoenix v6.0's TPE and AME while retaining the full instruction set architecture (ISA) compatibility. This enables seamless software migration from edge (Hawk v5.2) to edge-server (Phoenix-E v6.1) to datacenter (Phoenix v6.0).
---

## 2. Design Philosophy: Scale-Down, Not Scale-Out
| Aspect | Phoenix v6.0 | Phoenix-E v6.1 | Rationale |
|:---|:---|:---|:---|
| **TPE Tiles** | 8 × 16×16 | **6 × 16×16** | 25% reduction |
| **AME Blocks** | 16 × 8×8 | **12 × 8×8** | 25% reduction |
| **Memory Interface** | 512-bit CHI | **256-bit CHI** | Bandwidth/cost optimization |
| **Frequency** | 3.2 GHz | **2.5 GHz** | 7nm vs 5nm power envelope |
| **SRAM** | 144 KB | **108 KB** | Proportional scaling |
| **ISA** | WMMA + SpMM | **WMMA + SpMM (identical)** | Full software compatibility |
| **Peak INT8** | 16 TOPS | **12 TOPS** | ~75% of flagship |
**Key Insight**: Phoenix-E is not a different architecture — it is Phoenix with fewer tiles and a narrower memory interface. The same compiler, same drivers, same models run unmodified.
---

## 3. Microarchitecture
### 3.1 Block Diagram
```
+-----------------------------------------------------------------------+
|                 Phoenix-E AI Subsystem (v6.1)                         |
|                     12 TOPS @ 2.5GHz                                  |
+-----------------------------------------------------------------------+
|                                                                       |
|  +---------------------------+    +---------------------------+      |
|  |     TPE v6.1              |    |     AME v6.1              |      |
|  |  (Dense Tensor)           |    |  (Sparse Matrix)          |      |
|  |                           |    |                           |      |
|  |  6 tiles x 16x16 MAC      |    |  12 blocks x 8x8 MAC      |      |
|  |  = 1,536 MACs             |    |  = 768 MACs               |      |
|  |                           |    |                           |      |
|  |  INT8/FP16/BF16/FP32      |    |  INT8/FP16                |      |
|  |  WMMA ISA                 |    |  CSR / 2:4 Sparsity       |      |
|  |  GELU/SiLU/Softmax HW     |    |  Skip-zero Power Gating   |      |
|  |  72 KB SRAM (12KB/tile)   |    |  36 KB SRAM               |      |
|  +------------+--------------+    +------------+--------------+      |
|               |                                |                      |
|               v                                v                      |
|        +------+------+                  +------+------+               |
|        | 384-wide    |                  | 192-wide    |               |
|        | Accumulator |                  | Accumulator |               |
|        | 384 x 32b   |                  | 192 x 32b   |               |
|        +------+------+                  +------+------+               |
|               |                                |                      |
|               v                                v                      |
|        +------+------+                  +------+------+               |
|        | Post-Process|                  | Post-Process|               |
|        | ReLU/GELU/  |                  | ReLU/GELU/  |               |
|        | Quant/Scale |                  | LayerNorm   |               |
|        +------+------+                  +------+------+               |
|               |                                |                      |
|               +----------------+----------------+                      |
|                                |                                      |
|                         +------+------+                               |
|                         |  CHI/AXI4   |                               |
|                         |  256-bit    |  Coherent links               |
|                         +-------------+                               |
+-----------------------------------------------------------------------+
```

### 3.2 TPE v6.1 — Downscaled Tensor Engine
| Feature | Specification |
|:---|:---|
| Tile Count | 6 (down from 8) |
| MAC Array per Tile | 16 × 16 = 256 MACs |
| Total MACs | 1,536 |
| Data Types | INT8, FP16 (IEEE), BF16, FP32 |
| Accumulator | 32-bit (INT8/FP16), 64-bit (FP32) |
| SRAM per Tile | 12 KB |
| Total SRAM | 72 KB |
| Peak INT8 | 1,536 × 2 × 2.5 GHz = **7.68 TOPS** |

### 3.3 AME v6.1 — Downscaled Adaptive Engine
| Feature | Specification |
|:---|:---|
| Sparse Blocks | 12 (down from 16) |
| Block Size | 8 × 8 = 64 MACs per block |
| Total MACs | 768 |
| Peak INT8 (dense-equiv) | 768 × 2 × 2.5 GHz = **3.84 TOPS** |
| SRAM | 36 KB |

### 3.4 Combined Performance
```
TPE:  7.68 TOPS
AME: 3.84 TOPS (dense-equivalent)
Total: ~11.5 TOPS → marketed as 12 TOPS
```

---

## 4. ISA Compatibility
Phoenix-E uses the **exact same ISA** as Phoenix v6.0. The only difference is that commands targeting tiles 6-7 or blocks 12-15 will return a configuration error (tile not present).
| Instruction | Phoenix v6.0 | Phoenix-E v6.1 | Behavior |
|:---|:---|:---|:---|
| `tpe.wmma` tiles 0-5 | ✅ | ✅ | Normal operation |
| `tpe.wmma` tiles 6-7 | ✅ | ❌ Error | Tile not present |
| `ame.spmm` blocks 0-11 | ✅ | ✅ | Normal operation |
| `ame.spmm` blocks 12-15 | ✅ | ❌ Error | Block not present |
**Software Impact**: None for properly written code. The runtime library queries `NUM_TILES` and `NUM_BLOCKS` at initialization.
---

## 5. Performance Analysis
### 5.1 LLM Benchmarks (Estimated, batch=1)
| Model | Params | Phoenix-E Latency | Phoenix v6.0 Latency | Ratio |
|:---|:---|:---|:---|:---|
| Qwen3-1.8B | 1.8B | ~60 ms/token | ~45 ms/token | 1.33× |
| Qwen3-7B | 7B | ~160 ms/token | ~120 ms/token | 1.33× |
| Qwen3-14B | 14B | ~290 ms/token | ~220 ms/token | 1.33× |
| BERT-Base | 110M | ~45 ms | ~35 ms | 1.29× |
| ViT-Base | 86M | ~32 ms | ~25 ms | 1.28× |

### 5.2 Batch Inference Throughput (batch=8)
| Model | Phoenix-E Throughput | Phoenix v6.0 Throughput | Notes |
|:---|:---|:---|:---|
| Qwen3-7B | ~50 tok/s | ~66 tok/s | Edge server deployment |
| ResNet-50 | ~400 img/s | ~520 img/s | Image classification |

---

## 6. Power & Area Estimates
| Component | Phoenix v6.0 | Phoenix-E v6.1 | Reduction |
|:---|:---|:---|:---|
| TPE Logic | ~5.5 mm² | **~4.1 mm²** | 25% |
| TPE SRAM | ~1.0 mm² | **~0.75 mm²** | 25% |
| AME Logic | ~1.5 mm² | **~1.1 mm²** | 25% |
| AME SRAM | ~0.5 mm² | **~0.38 mm²** | 25% |
| **Total Area** | **~8.5 mm²** | **~6.3 mm²** | **26%** |
| **Dynamic Power** | ~13.2 W | **~7.5 W** | **43%** |
| **Total Power** | <15 W | **<8 W** | **47%** |

---

## 7. Target Applications
| Application | Why Phoenix-E? |
|:---|:---|
| **Industrial AI Gateway** | 8W TDP fits fanless enclosure, runs real-time defect detection |
| **Smart NVR** | 12 TOPS enables 16-channel AI analytics on edge |
| **Medical Imaging Workstation** | FP32 support for DICOM processing, low latency for interactive use |
| **Autonomous Vehicle ECU** | AEC-Q100 7nm viable, CHI coherent with vehicle SoC |
| **5G Base Station** | Real-time L1/L2 AI optimization, 256-bit interface matches ORAN fronthaul |

---

## 8. Integration Guide
### 8.1 SoC Connection
Same as Phoenix v6.0, but with 256-bit data path:
- **CHI/AXI4 Interface**: 256-bit coherent links
- **CSR Interface**: Core 0 configures via memory-mapped CSRs
- **Command FIFO**: 1024-entry queue
- **Interrupts**: TPE_DONE → PLIC #16, AME_DONE → PLIC #17
### 8.2 Software Migration
```c
// Code written for Phoenix v6.0 runs unchanged on Phoenix-E v6.1
phoenix_init(8, 16);  // Request 8 tiles, 16 blocks
// Runtime auto-detects: only 6 tiles, 12 blocks available
// Adjusts tiling strategy automatically, no code change needed
```

---

## 9. Comparison Summary
| Feature | Hawk v5.2 | Phoenix-E v6.1 | Phoenix v6.0 | Notes |
|:---|:---|:---|:---|:---|
| **Peak INT8** | 8 TOPS | **12 TOPS** | 16 TOPS | Linear scaling |
| **Process** | 7nm | **7nm** | 5nm | Same node as Hawk |
| **Memory IF** | AXI4 256-bit | **CHI 256-bit** | CHI 512-bit | Coherent vs non-coherent |
| **TDP** | <3W | **<8W** | <15W | Clear segmentation |
| **ISA** | FMX2 | **WMMA + SpMM** | WMMA + SpMM | v6.x unified |
| **Sparse** | No | **Yes (AME)** | Yes (AME) | Key differentiator |
| **Target** | Edge device | **Edge server** | Datacenter | Market positioning |
