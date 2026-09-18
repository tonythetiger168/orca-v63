# ORCA v6.0 ZEN — Phoenix AI Subsystem Architecture Specification
**Version**: 1.0  **Date**: 2026-09-05  **Target**: Server-class AI / LLM Inference / Multi-modal
---

## 1. Overview
Phoenix is the flagship AI accelerator subsystem for the ORCA v6.0 ZEN series. It combines two specialized engines to deliver **16 TOPS** peak INT8 performance at 3.2 GHz on a 5 nm process:
- **TPE (Tensor Processing Engine)**: Dense tensor operations, 12 TOPS
- **AME (Adaptive Matrix Engine)**: Sparse matrix acceleration, 4 TOPS (dense-equivalent).
Phoenix is designed to run large language models (LLM) such as Qwen3-235B-A22B and DeepSeek-V3-671B with hardware-native efficiency.
---

## 2. Subsystem Architecture
### 2.1 Top-Level Block Diagram
```
+-----------------------------------------------------------------------+
|                    Phoenix AI Subsystem (v6.0)                        |
|                        16 TOPS @ 3.2GHz                               |
+-----------------------------------------------------------------------+
|                                                                       |
|  +---------------------------+    +---------------------------+      |
|  |     TPE Engine            |    |     AME Engine            |      |
|  |  (Dense Tensor)           |    |  (Sparse Matrix)          |      |
|  |                           |    |                           |      |
|  |  8 tiles x 16x16 MAC      |    |  16 blocks x 8x8 MAC      |      |
|  |  = 2,048 MACs             |    |  = 1,024 MACs             |      |
|  |                           |    |                           |      |
|  |  INT8/FP16/BF16/FP32      |    |  INT8/FP16                |      |
|  |  WMMA ISA                 |    |  CSR / 2:4 Sparsity       |      |
|  |  GELU/SiLU/Softmax HW     |    |  Skip-zero Power Gating   |      |
|  |  96 KB SRAM (12KB/tile)   |    |  48 KB SRAM               |      |
|  +------------+--------------+    +------------+--------------+      |
|               |                                |                      |
|               v                                v                      |
|        +------+------+                  +------+------+               |
|        | 512-wide    |                  | 256-wide    |               |
|        | Accumulator |                  | Accumulator |               |
|        | 512 x 32b   |                  | 256 x 32b   |               |
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
|                         |  CHI.E/F    |                               |
|                         |  Mesh NoC   |  256-bit coherent links       |
|                         |  4x4 topology|                               |
|                         +-------------+                               |
|                                                                       |
|  Command Interface: Core 0 CSR (memory-mapped)                        |
|  Instruction FIFO: 1024-depth command queue                           |
|  Interrupt: TPE_IRQ (PLIC #16), AME_IRQ (PLIC #17)                    |
+-----------------------------------------------------------------------+
```

---

## 3. TPE — Tensor Processing Engine
### 3.1 Architecture
| Feature | Specification |
|:---|:---|
| Tile Count | 8 |
| MAC Array per Tile | 16 × 16 = 256 MACs |
| Total MACs | 2,048 |
| Data Types | INT8, FP16 (IEEE), BF16, FP32 |
| Accumulator | 32-bit (INT8), 32-bit (FP16/BF16), 64-bit (FP32) |
| SRAM per Tile | 12 KB (weight 8KB + activation 4KB) |
| Total SRAM | 96 KB |
| Instruction | WMMA (Warp Matrix Multiply Accumulate) |
| Peak (INT8) | 12 TOPS @ 3.2 GHz |

### 3.2 WMMA Instruction Set
| Instruction | Encoding | Description |
|:---|:---|:---|
| `tpe.wmma.m16n16k16 rd, rs1, rs2` | `custom-1, funct3=000` | C[16×16] += A[16×16] × B[16×16] |
| `tpe.wmma.m32n8k16 rd, rs1, rs2` | `custom-1, funct3=001` | C[32×8] += A[32×16] × B[16×8] |
| `tpe.wmma.m8n32k16 rd, rs1, rs2` | `custom-1, funct3=010` | C[8×32] += A[8×16] × B[16×32] |
| `tpe.load.tile rd, rs1, imm` | `custom-1, funct3=011` | Load tile from [rs1+imm] to tile SRAM |
| `tpe.store.tile rs1, rd, imm` | `custom-1, funct3=100` | Store tile from rd to [rs1+imm] |
| `tpe.gelu rd, rs1` | `custom-1, funct3=101` | GELU activation on tile |
| `tpe.quant rd, rs1, rs2` | `custom-1, funct3=110` | Quantize tile with scale/rs2 |

### 3.3 GELU Hardware Approximation
The TPE implements a piecewise-linear GELU approximation for hardware efficiency:
```
gelu(x) ≈ 0.5 * x * (1 + tanh(√(2/π) * (x + 0.044715 * x³)))
Hardware: 4-segment LUT + linear interpolation
Error: < 0.5% vs. software reference
```

---

## 4. AME — Adaptive Matrix Engine
### 4.1 Architecture
| Feature | Specification |
|:---|:---|
| Sparse Blocks | 16 |
| Block Size | 8 × 8 = 64 MACs per block |
| Total MACs | 1,024 |
| Sparsity Format | 2:4 structured, CSR (Compressed Sparse Row) |
| Data Types | INT8, FP16 |
| Skip-Zero Logic | Hardware row-empty detection, cycle gating |
| SRAM | 48 KB (index 16KB + value 32KB) |
| Peak (INT8, dense-equiv) | 4 TOPS @ 3.2 GHz |

### 4.2 Sparse Operation Flow
1. **Load CSR**: DMA fetches row_ptr, col_idx, values from DDR
2. **Skip-Zero Detect**: Hardware checks if row has non-zero elements
3. **Block Compute**: Only non-zero blocks trigger MAC operations
4. **Power Gating**: Empty rows clock-gate automatically
5. **Store Result**: Write dense output vector to DDR
### 4.3 AME Instruction Set
| Instruction | Encoding | Description |
|:---|:---|:---|
| `ame.spmm rd, rs1, rs2` | `custom-1, funct3=111` | Sparse matrix × dense vector |
| `ame.block_mul rd, rs1, rs2` | `custom-2, funct3=000` | Block-sparse GEMM |
| `ame.load.sparse rd, rs1, imm` | `custom-2, funct3=001` | Load CSR structure |
| `ame.dynamic_shape rd, rs1, rs2` | `custom-2, funct3=010` | Configure dynamic M/N/K |

---

## 5. Performance Analysis
### 5.1 Peak Throughput
```
TPE:  2,048 MACs x 2 (INT8) x 3.2 GHz = 13,107 GMAC/s → 12 TOPS
AME: 1,024 MACs x 2 (INT8) x 3.2 GHz x 0.625 (sparsity overhead) = 4 TOPS dense-equiv
Total: 16 TOPS
```

### 5.2 LLM Benchmarks (Estimated, batch=1)
| Model | Parameters | Layers | Phoenix Latency | Throughput |
|:---|:---|:---|:---|:---|
| Qwen3-1.8B | 1.8B | 24 | ~45 ms/token | ~22 tok/s |
| Qwen3-7B | 7B | 28 | ~120 ms/token | ~8.3 tok/s |
| Qwen3-14B | 14B | 40 | ~220 ms/token | ~4.5 tok/s |
| Qwen3-235B-A22B (MoE) | 235B total, 22B active | 64 | ~350 ms/token | ~2.9 tok/s |
| DeepSeek-V3 (MoE) | 671B total, 37B active | 61 | ~480 ms/token | ~2.1 tok/s |

### 5.3 Vision Transformer Benchmarks
| Model | Image Size | Phoenix Latency | Notes |
|:---|:---|:---|:---|
| ViT-Base | 224×224 | ~8 ms | 86M params |
| ViT-Large | 224×224 | ~22 ms | 307M params |
| SAM-B | 1024×1024 | ~180 ms | Image segmentation |

---

## 6. Power & Area Estimates
| Component | Area | Dynamic Power | Leakage Power |
|:---|:---|:---|:---|
| TPE Logic | ~5.5 mm² | ~10 W @ 3.2GHz | ~1.5 W |
| TPE SRAM (96KB) | ~1.0 mm² | ~0.5 W | ~0.2 W |
| AME Logic | ~1.5 mm² | ~2.5 W @ 3.2GHz | ~0.4 W |
| AME SRAM (48KB) | ~0.5 mm² | ~0.2 W | ~0.1 W |
| **Total Phoenix** | **~8.5 mm²** | **~13.2 W** | **~2.2 W** |
| **Total (typical)** | — | **<15 W** | — |

---

## 7. Software Stack
### 7.1 Compilation Flow
```
PyTorch 2.0 Model
    ↓
torch.compile(mode='reduce-overhead')
    ↓
ORCA Triton Backend (custom)
    ↓
MLIR TPE/AME Dialect
    ↓
orca-mlir-opt --convert-to-tpe-ame
    ↓
LLVM IR (RISC-V + custom intrinsics)
    ↓
orca-llvm-llc -march=riscv64 -mcpu=phoenix
    ↓
ELF Binary (host + accelerator kernels)
```

### 7.2 Runtime Stack
| Layer | Component | Description |
|:---|:---|:---|
| Application | PyTorch, TensorFlow, ONNX Runtime | Standard frameworks |
| Compiler | ORCA-MLIR, ORCA-LLVM | Custom backend |
| Runtime | libphoenix.so | Kernel scheduler, memory manager |
| Driver | /dev/orca_npu | Linux kernel driver |
| Hardware | TPE + AME | Phoenix engines |

---

## 8. Integration Guide
### 8.1 SoC Connection
Phoenix connects to the ORCA v6.0 ZEN SoC via:
- **CHI.E/F Mesh NoC**: 512-bit coherent data links to L3 cache and DDR controllers
- **CSR Interface**: Core 0 configures Phoenix via memory-mapped CSRs (`0x7C0`-`0x7CF`)
- **Command FIFO**: 1024-entry queue for batched TPE/AME commands
- **Interrupts**: TPE_DONE → PLIC #16, AME_DONE → PLIC #17
### 8.2 Multi-Core Coordination
In a 4-core ZEN configuration:
- **Core 0**: AI controller — dispatches commands, manages memory
- **Core 1-3**: Pre/post-processing — tokenization, detokenization, data augmentationPhoenix operates asynchronously; cores submit command batches and poll completion.
---

## 9. Verification Status
| Item | Status |
|:---|:---|
| RTL Lint (Verilator) | Pending |
| TPE Systolic Array Unit Test | Pending |
| AME Sparse Compute Unit Test | Pending |
| WMMA Instruction Decode Test | Pending |
| CHI NoC Integration Test | Pending |
| LLM Inference End-to-End | Future |
| FPGA Emulation (Alveo U55C) | Future |
