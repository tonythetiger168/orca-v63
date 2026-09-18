# ORCA v5.0 X — Kestrel NPU Architecture Specification
**Version**: 1.0  **Date**: 2026-09-05  **Target**: Edge AI / IoT / TinyML
---

## 1. Overview
Kestrel is the lightweight AI accelerator for the ORCA v5.0 X series. It delivers **1 TOPS** peak INT8 performance at 1 GHz while consuming less than 150 mW in a 22 nm process. The design prioritizes area efficiency, deterministic latency, and ease of integration over raw throughput.
---

## 2. Microarchitecture
### 2.1 Block Diagram
```
+-----------------------------------------------------------+
|                     Kestrel NPU v5.0                      |
+-----------------------------------------------------------+
|  AXI4-Lite Config  |        AXI4 DMA (64-bit)             |
|  (memory-mapped)   |                                      |
+----------+---------+------------------+-------------------+
           |                            |
           v                            v    
+------+------+             +------------------+
    | Config      |             | Weight SRAM      |
    | Registers   |             | 4 KB (1K x 32b)  |    +------+------+             +--------+---------+           |                            |
           v                            v    
+------+------+             +------------------+
    | Activation  |             | 8 x MAC Array    |
    | SRAM 4KB    |             | INT8 / INT16     |    +------+------+             | 3-cycle pipe     |           |                            +--------+---------+           |                                     |
           v                                     v    
+------+------+                      +------------------+
    | Accumulator |                      | ReLU / ReLU6 /   |
    | 8 x 32-bit  |                      | Pass-through     |    +------+------+                      +--------+---------+           |                                     |           +------------------+------------------+                              v                    
+------------------+
                    | Result Buffer    |                    | 256 x 32-bit     |                    +------------------+
```

### 2.2 MAC Array
| Feature | Specification |
|:---|:---|
| MAC Units | 8 parallel multipliers |
| Data Width | INT8 (primary), INT16 (optional) |
| Accumulator | 32-bit signed |
| Pipeline | 3 cycles (mul → acc → saturate) |
| Throughput | 8 ops/cycle @ INT8 → 8 GMAC/s @ 1 GHz |

### 2.3 Memory Hierarchy
| Level | Size | Organization | Access Latency |
|:---|:---|:---|:---|
| Weight SRAM | 4 KB | 1024 x 32-bit | 1 cycle |
| Activation SRAM | 4 KB | 1024 x 32-bit | 1 cycle |
| Result Buffer | 1 KB | 256 x 32-bit | 1 cycle |
| External DDR | — | AXI4 64-bit | Bus dependent |

---

## 3. Supported Operators
| Operator | Data Type | Notes |
|:---|:---|:---|
| Conv2D 1x1 | INT8, INT16 | Pointwise convolution |
| Conv2D 3x3 Depthwise | INT8, INT16 | Depthwise separable |
| Fully Connected | INT8, INT16 | Matrix-vector / matrix-matrix |
| ReLU | INT8, INT16 | max(0, x) |
| ReLU6 | INT8 | min(max(0, x), 6) |
| MaxPool 2x2 | INT8 | Down-sampling |
| AvgPool 2x2 | INT8 | Down-sampling |

---

## 4. Programming Interface
### 4.1 Memory-Mapped Configuration Registers
Base address: `0x4000_0000` (configurable in SoC integration)
| Offset | Name | Width | R/W | Description |
|:---|:---|:---|:---|:---|
| 0x0000 | CFG_M | 16 | R/W | Matrix M dimension (rows of output) |
| 0x0004 | CFG_N | 16 | R/W | Matrix N dimension (cols of output) |
| 0x0008 | CFG_K | 16 | R/W | Matrix K dimension (inner dimension) |
| 0x000C | WGT_BASE | 32 | R/W | DDR base address for weight DMA |
| 0x0010 | ACT_BASE | 32 | R/W | DDR base address for activation DMA |
| 0x0014 | RES_BASE | 32 | R/W | DDR base address for result write-back |
| 0x0018 | ACT_MODE | 3 | R/W | 0=ReLU, 1=ReLU6, 2=Reserved, 3=Pass-through |
| 0x001C | START | 1 | W | Write 1 to start computation |
| 0x0020 | STATUS | 32 | R | Bit 0: busy, Bit 1: done, Bits 31:16: ops counter low |
| 0x0100-0x04FF | WGT_SRAM | 32 x 1K | R/W | Weight SRAM direct access (debug) |
| 0x0500-0x08FF | ACT_SRAM | 32 x 1K | R/W | Activation SRAM direct access (debug) |

### 4.2 Operation Sequence
1. Write `CFG_M`, `CFG_N`, `CFG_K` to define GEMM dimensions
2. Write `WGT_BASE`, `ACT_BASE`, `RES_BASE` for DMA addresses
3. Write `ACT_MODE` to select post-processing function
4. Write `START = 1` to trigger computation
5. Poll `STATUS` register or wait for `npu_irq` interrupt
6. Read result from DDR at `RES_BASE`
---

## 5. Performance Analysis
### 5.1 Peak Throughput
```
Peak TOPS = MAC_UNITS x 2 (INT8) x Frequency
        = 8 x 2 x 1.0 GHz = 16 GMAC/s = 1.0 TOPS (INT8)
```

### 5.2 Typical CNN Layer Efficiency
| Layer Type | MACs | Cycles (est.) | Efficiency |
|:---|:---|:---|:---|
| Conv2D 1x1 (32→64, 14x14) | 401,408 | ~50,200 | ~80% |
| Depthwise 3x3 (64, 14x14) | 112,896 | ~14,200 | ~80% |
| FC (128→10) | 1,280 | ~200 | ~80% |

---

## 6. Power & Area Estimates
| Metric | Value | Notes |
|:---|:---|:---|
| Area | ~0.3 mm² @ 22nm | Excluding SRAM |
| SRAM Area | ~0.15 mm² | 9 KB total |
| Dynamic Power | ~120 mW @ 1 GHz, 100% activity | INT8 MAC array |
| Leakage Power | ~15 mW @ 22nm | Room temperature |
| Total Power | <150 mW | Typical workload |

---

## 7. Integration Guide
### 7.1 SoC Connection
Kestrel connects to the ORCA v5.0 X SoC as:
- **AXI4-Lite Slave**: CPU configures NPU via memory-mapped registers
- **AXI4 Master**: NPU performs DMA to/from DDR/SRAM via crossbar
### 7.2 Interrupt
The `npu_irq` signal is connected to the PLIC (Platform-Level Interrupt Controller) as IRQ source 8. The CPU handler should:
1. Acknowledge interrupt by reading `STATUS` register
2. Clear interrupt by writing 0 to `START`
3. Schedule next inference layer
---

## 8. Verification Status
| Item | Status |
|:---|:---|
| RTL Lint (Verilator) | Pending |
| Unit Testbench | Pending |
| SoC Integration Test | Pending |
| FPGA Prototype | Future |
