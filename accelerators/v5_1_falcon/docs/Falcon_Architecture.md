# ORCA v5.1 X+ — Falcon NPU Architecture Specification
**Version**: 1.0  **Date**: 2026-09-05  **Target**: Edge AI / Vision / Light NLP
---

## 1. Overview
Falcon is the vector-accelerated AI engine for the ORCA v5.1 X+ series. It couples tightly with the RVV 1.0 vector unit and adds a **Falcon Matrix Extension (FMX)** — a 32×32 dual systolic array that delivers **4 TOPS** peak INT8 performance at 1.5 GHz. The design bridges the gap between lightweight edge and high-performance AI.
---

## 2. Microarchitecture
### 2.1 Block Diagram
```
+---------------------------------------------------------------+
|                    Falcon NPU v5.1                            |
+---------------------------------------------------------------+
|  CPU Core (RV64GCV)  |  Vector Unit (VLEN=128, 4 lanes)       |
|         ↑↓           |         ↑↓                              |
+---------+------------+---------+------------------------------+
          |                      |
          v                      v   
+--------------------+   +---------------------------+
   | Vector Register    |   |      FMX Engine           |   | File (32 x 128b)   |   |  +---------------------+  |   | v0-v31, vtype, vl  |   |  | Systolic Array A    |  |   +--------+-----------+   |  | 32 x 32 INT8/FP16   |  |            |               |  +---------------------+  |            |               |  | Systolic Array B    |  |
            v               |  | 32 x 32 INT8/FP16   |  |   +--------+--------+
      |  +---------------------+  |   | Tile SRAM         |
      |           |               |   | 16KB Weight       |
      |     +-----+-----+         |   | 16KB Activation   |
      |
     | Accum | 256x32b |         |   +--------+--------+      |     +-----+-----+         |            |               |           |               |
            v               |
           v               |   +--------+--------+
      |     +-----+-----+         |   | Quantization &    |
      |
     | ReLU/ | Quant |         |   | Activation Unit   |
      |
     | GELU  | Scale |         |   +-------------------+      |     +-----+-----+         |                              +---------------------------+
```

### 2.2 FMX — Falcon Matrix Extension
FMX is a custom instruction set extension operating in the RISC-V `custom-0` opcode space (`opcode = 0x0b`). It enables direct matrix-tile operations without explicit load/store sequences.
#### FMX Instruction Formats
| Instruction | Opcode | funct3 | Description |
|:---|:---|:---|:---|
| `fmx.mmacc vd, vs2, vs1, vm` | `0101011` | `000` | Matrix multiply-accumulate: tile(vd) += tile(vs2) × tile(vs1) |
| `fmx.mload vd, rs1, imm` | `0101011` | `001` | Load matrix tile from memory [rs1+imm] into vd tile SRAM |
| `fmx.mstore vs3, rs1, imm` | `0101011` | `010` | Store matrix tile from vs3 to memory [rs1+imm] |
| `fmx.quant vd, vs2, rs1` | `0101011` | `011` | Quantize: vd = quantize(vs2, scale=rs1[15:0], zp=rs1[23:16]) |
| `fmx.relu vd, vs2, imm` | `0101011` | `100` | ReLU/ReLU6/Hardswish on tile |
| `fmx.scale vd, vs2, rs1` | `0101011` | `101` | Per-channel rescaling for INT8 output |

### 2.3 Systolic Array
| Feature | Array A | Array B |
|:---|:---|:---|
| Dimensions | 32 × 32 | 32 × 32 |
| Data Type | INT8 / FP16 | INT8 / FP16 |
| MACs | 1,024 | 1,024 |
| Accumulator | 32-bit | 32-bit |
| Throughput | 1,024 ops/cycle | 1,024 ops/cycle |
| Pipeline | Systolic wavefront | Systolic wavefront |
**Combined Peak**: 2,048 MACs × 2 (INT8) × 1.5 GHz = **4 TOPS**
---

## 3. Supported Data Types
| Type | Bits | MAC Support | Notes |
|:---|:---|:---|:---|
| INT8 | 8 | Full | Primary, 2x throughput |
| INT16 | 16 | Full | 1x throughput |
| FP16 (IEEE 754) | 16 | Full | 1x throughput |
| BF16 | 16 | Full | 1x throughput, wider range |

---

## 4. Programming Model
### 4.1 Assembly Example: Conv2
D Layer
```asm
# Falcon Conv2D 3x3 example
# Tile dimensions: 32x32, input channels = 64, output channels = 128
    li      t0, 0x80000000          # weight base address
    li      t1, 0x90000000          # activation base address
    li      t2, 0xA0000000          # result base address    # Load weight tile
    fmx.mload v4, t0, 0             # v4 = weight[0:31, 0:31]    # Load activation tile
    fmx.mload v8, t1, 0             # v8 = activation[0:31, 0:31]    # Matrix multiply-accumulate
    fmx.mmacc v12, v8, v4           # v12 += v8 * v4    # Apply ReLU
    fmx.relu  v12, v12, 0           # ReLU    # Quantize to INT8
    fmx.quant v16, v12, t3          # v16 = quantize(v12, scale=t3)    # Store result
    fmx.mstore v16, t2, 0
```

### 4.2 C Intrinsic API
```c
// Falcon C intrinsics (provided by orca-gcc)
#include <orca_fmx.h>
// Matrix tile type
typedef int8_t fmx_tile_t[32][32];
// Load tile from memory
void fmx_mload(fmx_tile_t* dst, void* src);
// Matrix multiply-accumulate
void fmx_mmacc(fmx_tile_t* acc, fmx_tile_t* a, fmx_tile_t* b);
// Activation
void fmx_relu(fmx_tile_t* dst, fmx_tile_t* src, int mode);
// Quantization
void fmx_quant(fmx_tile_t* dst, fmx_tile_t* src, int16_t scale, int8_t zp);
```

---

## 5. Performance Analysis
### 5.1 Peak Throughput
```
Peak TOPS = 2 arrays x 1,024 MACs x 2 (INT8) x 1.5 GHz
        = 4,096 x 1.5 = 6,144 GMAC/s → ~4.0 TOPS (accounting for overhead)
```

### 5.2 Model Benchmarks (Estimated)
| Model | Params | Falcon Latency | Notes |
|:---|:---|:---|:---|
| MobileNet v2 | 3.5M | ~2.5 ms @ 1.5GHz | ImageNet 224x224 |
| EfficientNet-Lite0 | 5.4M | ~4.0 ms @ 1.5GHz | ImageNet 224x224 |
| BERT-Tiny | 4.4M | ~3.0 ms @ 1.5GHz | Sequence length 128 |
| Whisper Tiny | 39M | ~25 ms @ 1.5GHz | 30s audio |

---

## 6. Power & Area Estimates
| Metric | Value | Notes |
|:---|:---|:---|
| Logic Area | ~1.2 mm² @ 12nm | Systolic arrays + control |
| SRAM Area | ~0.6 mm² | 32 KB tile SRAM |
| Total Area | ~1.8 mm² | — |
| Dynamic Power | ~650 mW @ 1.5 GHz, 100% | INT8 dual-array |
| Leakage Power | ~80 mW @ 12nm | — |
| Total Power | <800 mW | Typical vision workload |

---

## 7. Integration Guide
### 7.1 SoC Connection
Falcon integrates with the ORCA v5.1 X+ SoC as:
- **RVV Register Interface**: Direct access to VRF (v0-v31) for tile operands
- **FMX Decode Path**: Custom decoder extension for `opcode = 0x0b` instructions
- **AXI4 Master**: 128-bit wide DMA for tile load/store to DDR
### 7.2 Software Stack
| Layer | Component |
|:---|:---|
| Framework | TensorFlow Lite, ONNX Runtime |
| Compiler | orca-gcc with `-mfmx` flag |
| Runtime | libfalcon.so (tile scheduler, kernel library) |
| Kernel | Hand-optimized assembly for common operators |

---

## 8. Verification Status
| Item | Status |
|:---|:---|
| RTL Lint (Verilator) | Pending |
| FMX Instruction Decode Test | Pending |
| Systolic Array Unit Test | Pending |
| RVV Coupling Test | Pending |
| End-to-end Model Inference | Future |
