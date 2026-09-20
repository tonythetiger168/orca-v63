# ORCA v5.2 X++ — Hawk NPU Architecture Specification
**Version**: 1.0  **Date**: 2026-09-05  **Target**: High-Performance Edge AI / Light Server / Transformer Inference
---

## 1. Overview
Hawk is the high-performance edge AI accelerator for the ORCA v5.2 X++ series. It bridges the gap between Falcon (4 TOPS) and Phoenix (16 TOPS), delivering **8 TOPS** peak INT8 performance at 2.0 GHz on a 7 nm process. Hawk introduces **Transformer Block Hard-Acceleration** — a dedicated pipeline for LayerNorm, Multi-Head Attention, and Feed-Forward layers that dramatically speeds up LLM and Vision Transformer inference at the edge.
---

## 2. Microarchitecture
### 2.1 Block Diagram
```
+-----------------------------------------------------------------------+
|                    Hawk NPU v5.2 — 8 TOPS                             |
+-----------------------------------------------------------------------+
|  CPU Core (RV64GCV)  |  Vector Unit (VLEN=256, 8 lanes)             |
|         ↑↓           |         ↑↓                                     |
+---------+------------+---------+--------------------------------------+
          |                      |
          v                      v   
+--------------------+   +----------------------------------+
   | Vector Register    |   |         FMX2 Engine              |   | File (32 x 256b)   |   |  +---------------------------+   |   | v0-v31, vtype, vl  |   |  | Array 0 | Array 1 |
     |   +--------+-----------+   |  | 32x32   | 32x32   |
     |            |               |  | +---------------------------+   |
            v               |  | Array 2 | Array 3 |
     |   +--------+--------+      |  | 32x32   | 32x32   |
     |   | Tile SRAM         |
      |  +---------------------------+   |   | 32KB Weight       |
      |           |               |   | 32KB Activation   |
      |     +-----+-----+         |   +--------+--------+      |
     | Accum | 4Kx32b  |         |            |               |     +-----+-----+         |
            v               |
           v               |   +--------+--------+
      |     +------------------+    |   | Quantization &    |
      |
     | Transformer Block|    |   | Activation Unit   |
      |
     | Hard-Accel Pipe  |
    |   +-------------------+      |
     |                  |
    |                              |
     | LayerNorm        |
    |                              |
     | Q/K/V MatMul     |
    |                              |
     | Softmax          |
    |                              |
     | FF MatMul        |
    |                              |     +------------------+    |                              +---------------------------+
```

### 2.2 FMX2 — Falcon Matrix Extension v2
FMX2 expands on Falcon's FMX with 4× 32×32 systolic arrays and adds Transformer-specific instructions.
| Instruction | Opcode | funct3 | Description |
|:---|:---|:---|:---|
| `fmx2.mmacc vd, vs2, vs1, vm` | `0101011` | `000` | 4-array matrix multiply-accumulate |
| `fmx2.mload vd, rs1, imm` | `0101011` | `001` | Load tile to SRAM (256-bit burst) |
| `fmx2.mstore vs3, rs1, imm` | `0101011` | `010` | Store tile to memory |
| `fmx2.quant vd, vs2, rs1` | `0101011` | `011` | Quantize with scale/zp |
| `fmx2.xfmr vd, rs1, rs2` | `0101011` | `100` | **Transformer block hard-accel** |

### 2.3 Systolic Array
| Feature | Array 0-3 |
|:---|:---|
| Dimensions | 32 × 32 each |
| Data Type | INT8 / INT16 / FP16 / BF16 / FP32 |
| MACs per Array | 1,024 |
| Total MACs | **4,096** |
| Accumulator | 32-bit (INT8/FP16), 64-bit (FP32) |
| Throughput | 4,096 ops/cycle (all arrays) |
**Peak INT8**: 4,096 MACs × 2 (INT8) × 2.0 GHz = **8 TOPS**
### 2.4 Transformer Block Hard-Acceleration
Hawk includes a dedicated pipeline for executing a complete Transformer block in hardware:
```
Input ──→ LayerNorm ──→ Q MatMul ──┬──→ QK^T ──→ Softmax ──→ V MatMul ──→ Output
       │
                  └──→ K MatMul ──┘
                              └──→ FF (Up+Down) ──→ Residual
```
| Stage | Hardware Unit | Cycles (est.) | Notes |
|:---|:---|:---|:---|
| LayerNorm | Mean/Var accumulator + rsqrt LUT | ~seq_len | Per-token parallel |
| Q/K/V | 3× FMX2 arrays in parallel | ~tile_dim | MatMul with weights |
| QK^T | 1× FMX2 array | ~tile_dim | Attention scores |
| Softmax | exp LUT + reciprocal + accumulator | ~seq_len | Numerically stable |
| V | 1× FMX2 array | ~tile_dim | Attention output |
| FF Up | 2× FMX2 arrays | ~tile_dim | Expand 4x |
| FF Down | 2× FMX2 arrays | ~tile_dim | Project back |
| Residual | Vector add (RVV) | ~seq_len | Element-wise |

---

## 3. Supported Data Types
| Type | Bits | MAC Support | Transformer Support | Notes |
|:---|:---|:---|:---|:---|
| INT8 | 8 | Full | Full | Primary, 2x throughput |
| INT16 | 16 | Full | Full | 1x throughput |
| FP16 (IEEE 754) | 16 | Full | Full | 1x throughput |
| BF16 | 16 | Full | Full | 1x throughput, wider range |
| FP32 | 32 | Full | LayerNorm/Softmax only | 0.5x throughput |

---

## 4. Programming Model
### 4.1 Assembly Example: Transformer Block
```asm
# Hawk Transformer block example
# seq_len=128, head_dim=64, num_heads=8
    li      t0, 0x80000000          # input base
    li      t1, 0x90000000          # weight base
    li      t2, 0xA0000000          # output base    # Configure and run full transformer block    fmx2.xfmr v0, t0, t1            # v0 = TransformerBlock(input[t0], weights[t1])    # Result automatically written to output buffer
```

### 4.2 C Intrinsic API
```c
#include <orca/fmx2.h>
// Tile types (32x32 elements)
typedef int8_t  fmx2_tile_i8_t[32][32];
typedef __fp16  fmx2_tile_f16_t[32][32];
// Memory operations
void fmx2_mload_i8 (fmx2_tile_i8_t*  dst, const void* src);
void fmx2_mload_f16(fmx2_tile_f16_t* dst, const void* src);
// 4-array matrix multiply-accumulate
void fmx2_mmacc_i8 (fmx2_tile_i8_t*  acc[4], const fmx2_tile_i8_t*  a[4], const fmx2_tile_i8_t*  b[4]);
// Transformer block (hard-accelerated)
typedef struct {
    uint16_t seq_len;
    uint16_t head_dim;
    uint8_t  num_heads;
    uint8_t  num_layers;
} fmx2_xfmr_config_t;
void fmx2_transformer_block(
    void* output,
    const void* input,
    const void* weights,
    const fmx2_xfmr_config_t* config);
```

---

## 5. Performance Analysis
### 5.1 Peak Throughput
```
Peak TOPS = 4 arrays x 1,024 MACs x 2 (INT8) x 2.0 GHz
        = 8,192 x 2.0 = 16,384 GMAC/s → 8.0 TOPS (INT8)
Peak TFLOPS (FP16) = 4,096 x 2.0 = 8,192 MFLOP/s → 4.0 TFLOPS
```

### 5.2 Model Benchmarks (Estimated)
| Model | Params | Hawk Latency | Notes |
|:---|:---|:---|:---|
| MobileNet v3-Large | 5.4M | ~1.5 ms @ 2GHz | ImageNet 224x224 |
| EfficientNet-B0 | 5.3M | ~2.0 ms @ 2GHz | ImageNet 224x224 |
| ResNet-50 | 25.6M | ~5.0 ms @ 2GHz | ImageNet 224x224 |
| ViT-Base | 86M | ~25 ms @ 2GHz | 224x224, 12 layers |
| BERT-Base | 110M | ~35 ms @ 2GHz | Seq 128, 12 layers |
| BERT-Large | 340M | ~95 ms @ 2GHz | Seq 128, 24 layers |
| GPT-2 Small | 124M | ~40 ms/token @ 2GHz | 12 layers |
| LLaMA-7B | 7B | ~180 ms/token @ 2GHz | 32 layers (edge feasible) |

---

## 6. Power & Area Estimates
| Metric | Value | Notes |
|:---|:---|:---|
| Logic Area | ~2.5 mm² @ 7nm | 4 systolic arrays + control |
| SRAM Area | ~1.0 mm² | 64 KB tile SRAM + LUTs |
| Total Area | ~3.5 mm² | — |
| Dynamic Power | ~2.2 W @ 2.0 GHz, 100% | All arrays active |
| Leakage Power | ~0.3 W @ 7nm | — |
| Transformer Block | ~1.8 W | Typical LLM layer |
| Total Power | **<3 W** | Typical edge workload |

---

## 7. Integration Guide
### 7.1 SoC Connection
Hawk integrates with the ORCA v5.2 X++ SoC as:
- **RVV Register Interface**: VLEN=256, direct VRF access
- **FMX2 Decode Path**: Custom decoder for `opcode = 0x0b` instructions
- **AXI4 Master**: 256-bit wide DMA for tile load/store
- **Interrupt**: `npu_irq` → PLIC
### 7.2 Memory Map
| Region | Size | Description |
|:---|:---|:---|
| 0x5000_0000 | 4 KB | Hawk configuration registers |
| 0x5000_1000 | 32 KB | Weight tile SRAM (direct access) |
| 0x5000_9000 | 32 KB | Activation tile SRAM (direct access) |
| 0x5001_1000 | 4 KB | Transformer block config |
| 0x5001_2000 | 4 KB | Performance counters |

---

## 8. Comparison with Falcon (v5.1)
| Feature | Falcon v5.1 | Hawk v5.2 | Delta |
|:---|:---|:---|:---|
| **Peak INT8** | 4 TOPS | **8 TOPS** | **2×** ✅ |
| **VLEN** | 128 | **256** | **2×** ✅ |
| **Systolic Arrays** | 2 × 32×32 | **4 × 32×32** | **2×** ✅ |
| **Total MACs** | 2,048 | **4,096** | **2×** ✅ |
| **Frequency** | 1.5 GHz | **2.0 GHz** | **+33%** ✅ |
| **SRAM** | 32 KB | **64 KB** | **2×** ✅ |
| **Transformer Accel** | No | **Yes (hard-pipeline)** | **新增** ✅ |
| **Data Types** | INT8/INT16/FP16/BF16 | **+ FP32** | **擴展** ✅ |
| **AXI Width** | 128-bit | **256-bit** | **2×** ✅ |
| **Power** | <800 mW | <3 W | 增加 (性能提升更大) |
| **Process** | 12nm | **7nm** | 更先進 |
| **Area** | 1.8 mm² | 3.5 mm² | 增加 (合理) |

---

## 9. Verification Status
| Item | Status |
|:---|:---|
| RTL Lint (Verilator) | Pending |
| FMX2 Instruction Decode Test | Pending |
| 4-Array Systolic Compute Test | Pending |
| Transformer Block Pipeline Test | Pending |
| RVV-256 Coupling Test | Pending |
| End-to-end BERT/GPT-2 Inference | Future |
