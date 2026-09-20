# ORCA v6.2 ZEN — Phoenix+ Multi-Chip AI Subsystem Architecture Specification
**Version**: 1.0  **Date**: 2026-09-05  **Target**: Datacenter / AI Training / Large-Scale Inference
---

## 1. Overview
Phoenix+ is the **multi-chip scaled** variant of the Phoenix AI subsystem. It uses **UCIe (Universal Chiplet Interconnect Express)** to connect two Phoenix dies into a single coherent AI accelerator, delivering **32 TOPS** peak INT8 performance — exactly double the single-die Phoenix v6.0.
Phoenix+ is designed for datacenter deployment where rack space and power are constrained, but maximum throughput is required. It enables linear scaling from edge-server (Phoenix-E, 12 TOPS) to datacenter (Phoenix, 16 TOPS) to high-density datacenter (Phoenix+, 32 TOPS) using the same silicon die.
---

## 2. Design Philosophy: Scale-Out via Chiplets
| Aspect | Phoenix v6.0 | Phoenix+ v6.2 | Rationale |
|:---|:---|:---|:---|
| **Dies** | 1 | **2 (UCIe)** | Chiplet scaling |
| **TPE Tiles** | 8 × 16×16 | **2 × (8 × 16×16)** | Linear duplication |
| **AME Blocks** | 16 × 8×8 | **2 × (16 × 8×8)** | Linear duplication |
| **Memory IF** | 512-bit CHI | **2 × 512-bit CHI** | Per-die bandwidth |
| **Die-to-Die** | N/A | **UCIe 256-bit @ 16 GT/s** | Coherent interconnect |
| **Peak INT8** | 16 TOPS | **32 TOPS** | Perfect 2× scaling |
| **TDP** | <15W | **<30W** | Linear power scaling |
| **Area** | ~8.5 mm² | **2 × ~8.5 mm²** | Two dies on interposer |
**Key Insight**: Phoenix+ does not redesign the silicon — it takes two proven Phoenix v6.0 dies and connects them with UCIe. This minimizes risk, maximizes yield, and enables a single die design to serve three market segments.
---

## 3. Multi-Chip Architecture
### 3.1 Top-Level Block Diagram
```
+-----------------------------------------------------------------------+
|                    Phoenix+ AI Subsystem (v6.2)                       |
|                     32 TOPS @ 3.2GHz (dual-die)                       |
+-----------------------------------------------------------------------+
|                                                                       |
|  +------------------------+        +------------------------+        |
|  |      Die 0 (Master)    |<=======|      Die 1 (Slave)     |        |
|  |      16 TOPS           |  UCIe  |      16 TOPS           |        |
|  |                        | 256-bit|                        |        |
|  |  TPE: 8 tiles x 16x16  | 16GT/s |  TPE: 8 tiles x 16x16  |        |
|  |  AME: 16 blocks x 8x8  |        |  AME: 16 blocks x 8x8  |        |
|  |                        |        |                        |        |
|  |  CHI 512-bit to L3     |        |  CHI 512-bit to L3     |        |
|  |  Command Scheduler     |        |  Remote Command Exec   |        |
|  +-----------+------------+        +-----------+------------+        |
|              |                                |                       |
|              v                                v                       |
|       +------+------+                  +------+------+                |
|       | Shared L3   |                  | Shared L3   |                |
|       | 8MB per die |                  | 8MB per die |                |
|       +------+------+                  +------+------+                |
|              |                                |                       |
|              v                                v                       |
|       +------+------+                  +------+------+                |
|       | DDR5-6400 |                  | DDR5-6400 |                |
|       | 2x40-bit  |                  | 2x40-bit  |                |
|       +-----------+                  +-----------+                |
+-----------------------------------------------------------------------+
```

### 3.2 UCIe Die-to-Die Interface
| Parameter | Specification |
|:---|:---|
| Protocol | UCIe 1.0 |
| Data Width | 256-bit (per direction) |
| Data Rate | 16 GT/s (NRZ) |
| Bandwidth | 512 GB/s aggregate |
| Latency | <10 ns die-to-die |
| Coherency | Full cache coherency (CHI.C2C) |
| Link Training | Automatic, <1 ms |
| Error Handling | CRC + Retry (BER < 1e-15) |

### 3.3 Die Roles
| Role | Die 0 (Master) | Die 1 (Slave) |
|:---|:---|:---|
| **Command Source** | Receives commands from CPU CSR | Receives commands via D2D from Die 0 |
| **Scheduling** | Global work distribution | Local tile execution |
| **Memory** | Direct DDR access | Direct DDR access |
| **Interrupts** | TPE0_IRQ, AME0_IRQ | TPE1_IRQ, AME1_IRQ |
| **D2D TX** | Results to Die 1 | Results to Die 0 |
| **D2D RX** | Results from Die 1 | Commands from Die 0 |

---

## 4. Distributed Execution Model
### 4.1 Data Parallel (Recommended for LLM)
```
Input Batch ──→ Die 0 processes Batch[0:N/2-1]
     └──→ Die 1 processes Batch[N/2:N-1]
          └──→ D2D barrier
          └──→ Combined output
```

### 4.2 Tensor Parallel (For large matrices)
```
Matrix A ──→ Split column-wise ──→ Die 0: A[:, 0:M/2-1]
     └──→ Die 1: A[:, M/2:M-1]
          └──→ Both dies multiply with full B
          └──→ D2D all-reduce partial results
```

### 4.3 Pipeline Parallel (For deep models)
```
Layer 0-15 ──→ Die 0
     └──→ D2D handoff activations
     └──→ Layer 16-31 ──→ Die 1
          └──→ Final output
```

---

## 5. Performance Analysis
### 5.1 Scaling Efficiency
| Configuration | Peak INT8 | ResNet-50 | BERT-Large | Qwen3-7B |
|:---|:---|:---|:---|:---|
| Single Die (v6.0) | 16 TOPS | ~520 img/s | ~8.3 tok/s | ~8.3 tok/s |
| **Dual Die (v6.2)** | **32 TOPS** | **~1,040 img/s** | **~16.5 tok/s** | **~16.5 tok/s** |
| Scaling Efficiency | 100% | **~100%** | **~99%** | **~99%** |
**Near-linear scaling** is achieved because:
1. Each die has independent DDR controllers (no memory bandwidth contention)
2. UCIe bandwidth (512 GB/s) exceeds the compute-to-memory ratio
3. D2D latency (<10 ns) is negligible compared to compute time (~ms)
### 5.2 Multi-Chip Configurations (Future Roadmap)
| Configuration | Dies | TOPS | TDP | Target |
|:---|:---|:---|:---|:---|
| Phoenix+ 2D | 2 | 32 | <30W | Datacenter inference server |
| Phoenix+ 4D | 4 | 64 | <60W | Training node (small models) |
| Phoenix+ 8D | 8 | 128 | <120W | Large training cluster |

---

## 6. Power & Area Estimates
| Component | Per Die | Dual-Die (v6.2) | Notes |
|:---|:---|:---|:---|
| **Silicon Area** | ~8.5 mm² | **2 × ~8.5 mm²** | Two dies on interposer |
| **Interposer Area** | — | **~25 mm²** | UCIe routing + passive components |
| **Package** | FC-BGA | **2.5D CoWoS** | TSMC/Intel equivalent |
| **TDP** | <15W | **<30W** | Linear scaling |
| **Perf/Watt** | ~1.07 TOPS/W | **~1.07 TOPS/W** | Maintained at scale |
| **Perf/Area** | ~1.88 TOPS/mm² | **~1.88 TOPS/mm²** | Maintained at scale |

---

## 7. Software Stack for Multi-Chip
### 7.1 Runtime API
```c
#include <orca/phoenix_plus.h>
// Initialize dual-die subsystem
phoenix_plus_init(2);  // 2 dies
// Query topology
phoenix_plus_topology_t topo;
phoenix_plus_get_topology(&topo);
// topo.num_dies = 2
// topo.die[0].tpe_tiles = 8
// topo.die[1].tpe_tiles = 8
// Run inference with automatic work distribution
phoenix_plus_inference(model, input, output, PHOENIX_PLUS_AUTO_PARALLEL);
```

### 7.2 PyTorch Backend
```python
import torch
from orca.pytorch import PhoenixPlusCompiler
# Compile for dual-die Phoenix+
model = torch.compile(
    model,
    backend='phoenix_plus',
    mode='max-autotune',
    options={'num_dies': 2, 'parallel_strategy': 'data'})
```

---

## 8. Comparison with NVIDIA/AMD
| Product | NVIDIA H100 | AMD MI300X | ORCA Phoenix+ v6.2 | Notes |
|:---|:---|:---|:---|:---|
| **Peak (INT8)** | 3,958 TOPS | 2,600 TOPS | **32 TOPS** | Different leagues |
| **Peak (FP16)** | 1,979 TFLOPS | 1,300 TFLOPS | **16 TFLOPS** | |
| **TDP** | 700W | 750W | **<30W** | 20× lower power |
| **Process** | 4nm | 5nm | **5nm** | Same node |
| **Memory** | 80GB HBM3 | 192GB HBM3 | **DDR5-6400** | Cost-optimized |
| **Price (est.)** | $30,000 | $20,000 | **<$500** | 60× lower cost |
| **Use Case** | Training + Inference | Training + Inference | **Edge→Datacenter inference** | Different markets |
**Phoenix+ is not competing with H100/MI300X** — it targets the emerging market of **high-efficiency inference servers** where 32 TOPS at 30W is the sweet spot for edge datacenters, 5G MEC, and autonomous vehicle fleet servers.
---

## 9. Integration Guide
### 9.1 Package Diagram
```
+-------------------------------+
|        Organic Substrate      |
|  +-----------------------+    |
|  |    Silicon Interposer |    |
|  |  +-----+   +-----+    |    |
|  |  | Die |===| Die |    |    |
|  |  |  0  |UCI|  1  |    |    |
|  |  +--+--+   +--+--+    |    |
|  |     |         |       |    |
|  |   DDR0      DDR1      |    |
|  +-----------------------+    |
|        FC-BGA 2500 pins     |
+-------------------------------+
```

### 9.2 Pinout (Simplified)
| Group | Pins | Description |
|:---|:---|:---|
| DDR5 (Die 0) | 320 | 2x40-bit DDR5-6400 |
| DDR5 (Die 1) | 320 | 2x40-bit DDR5-6400 |
| PCIe 5.0 x16 | 64 | Host interface |
| UCIe (internal) | — | On-interposer, no package pins |
| Power | 200 | VDD, VSS, decoupling |
| GPIO/JTAG | 64 | Debug, bootstrap |
