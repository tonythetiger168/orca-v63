# ORCA RISC-V Processor + AI Accelerator — Unified Roadmap 2026-2028
**Version**: 2.0  **Date**: 2026-09-05  **Status**: Active Development
---

## Executive Summary
ORCA is a **unified RISC-V processor + AI accelerator ecosystem** spanning from ultra-low-power 32-bit MCUs to high-performance 64-bit server-class chips. This roadmap defines the complete product matrix across two CPU architectures (32-bit and 64-bit) and six AI accelerator generations.
```
+-----------------------------------------------------------------------+
|                    ORCA Unified Architecture                          |
+-----------------------------------------------------------------------+
|                                                                       |
|   32-bit MCU          64-bit Application         64-bit Server       |
|   +----------+        +----------------+        +----------------+   |
|   | ORCA     |        | ORCA v5.x      |        | ORCA v6.x ZEN  |   |
|   | 32-bit   |        | 64-bit         |        | 64-bit         |   |
|   | RV32IMC  |        | RV64GC(V)      |        | RV64GCV        |   |
|   | 1-2 cyc  |        | 4/8-issue OoO  |        | 8-issue OoO    |   |
|   | <100mW   |        | <5W            |        | <100W          |   |
|   +----+-----+        +----+-----------+        +----+-----------+   |
|        |                   |                      |                  |
|        |                   |                      |                  |
|   +----v-----+        +----v-----------+        +----v-----------+   |
|   | Kestrel  |        | Falcon / Hawk  |        | Phoenix Series |   |
|   | 1 TOPS   |        | 4-8 TOPS       |        | 12-32 TOPS     |   |
|   | INT8     |        | INT8/FP16      |        | INT8/FP16/BF16 |   |
|   | AXI4-Lite|        | AXI4/RVV       |        | CHI/WMMA       |   |
|   +----------+        +----------------+        +----------------+   |
|                                                                       |
|   Target: IoT/Edge    Target: Edge/Vision    Target: Server/DC     |
|                                                                       |
+-----------------------------------------------------------------------+
```

---

## Part 1: ORCA 32-bit CPU + AI Roadmap
### 1.1 ORCA 32-bit Processor Core
| Feature | Specification |
|:---|:---|
| **ISA** | RV32IMC (base), optional RV32IMCF (FP) |
| **Pipeline** | 2-stage or 3-stage in-order |
| **DMIPS/MHz** | 1.5-2.0 |
| **Area** | 0.1-0.3 mm² @ 22nm |
| **Power** | 10-50 µW/MHz |
| **Interrupt** | CLINT + 16-entry PLIC |
| **Debug** | RISC-V Debug Module 0.13 |
| **Peripherals** | UART, SPI, I2C, GPIO, PWM, ADC |

### 1.2 32-bit + Kestrel Integration (v5.0-MCU)
```
+-----------------------------------------------------------+
|              ORCA 32-bit MCU + Kestrel NPU                |
+-----------------------------------------------------------+
|                                                           |
|   +----------------+        +---------------------+       |
|   | ORCA 32-bit    |        | Kestrel NPU v5.0    |       |
|   | RV32IMC        |<======>| 1 TOPS INT8         |       |
|   | 2-stage pipe   | AXI4-L | 8 MAC array         |       |
|   | 32KB SRAM      |        | 4KB W + 4KB A SRAM  |       |
|   | 16MHz-100MHz   |        | ReLU/ReLU6          |       |
|   +----------------+        +---------------------+       |
|                                                           |
|   Target: Always-on voice, person detection, TinyML       |
+-----------------------------------------------------------+
```
| Parameter | Value |
|:---|:---|
| **CPU-NPU Interface** | AXI4-Lite 32-bit |
| **NPU Memory** | Shared SRAM (32KB total) |
| **Peak AI** | 1 TOPS @ 100MHz (INT8) |
| **Wake Word Latency** | <50 ms (Alexa/OK Google) |
| **Person Detection** | <100 ms @ QQVGA (160x120) |
| **Power** | <5 mW active, <50 µW sleep |

### 1.3 32-bit Software Stack
```bash
# Zephyr RTOS + TFLite Micro
west build -b orca_32bit samples/tflm_microspeech
# Bare-metal GCC
riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -DORCA_NPU_V5 app.c -o fw.elf
```

---

## Part 2: ORCA 64-bit v5.x CPU + AI Roadmap
### 2.1 v5.0 X — Application Processor (Existing)
```
+---------------------------------------------------------------+
|              ORCA v5.0 X 64-bit SoC + Kestrel                 |
+---------------------------------------------------------------+
|                                                               |
|   +------------------------+   +-------------------------+   |
|   | ORCA v5.0 CPU          |   | Kestrel NPU v5.0        |   |
|   | RV64GC                 |   | 1 TOPS INT8             |   |
|   | 4-issue OoO            |   | AXI4-Lite config        |   |
|   | 128 ROB                |   | AXI4 DMA                |   |
|   | Sv39 MMU               |   | 8 MAC array             |   |
|   | 1.5 GHz                |   | ReLU/ReLU6              |   |
|   +------------------------+   +-------------------------+   |
|                                                               |
|   Interconnect: AXI4 64-bit crossbar (4x4)                    |
|   Memory: DDR4/LPDDR4 via SRAM controller                     |
|                                                               |
+---------------------------------------------------------------+
```

### 2.2 v5.1 X+ — Vector + Falcon (Existing)
```
+---------------------------------------------------------------+
|              ORCA v5.1 X+ SoC + Falcon NPU                    |
+---------------------------------------------------------------+
|                                                               |
|   +------------------------+   +-------------------------+   |
|   | ORCA v5.1 CPU          |   | Falcon NPU v5.1         |   |
|   | RV64GCV (VLEN=128)     |   | 4 TOPS INT8             |   |
|   | 4-issue OoO            |   | RVV register coupling   |   |
|   | Vector Unit (4 lanes)  |   | FMX 32x32 dual array    |   |
|   | 1.5 GHz                |   | INT8/INT16/FP16/BF16    |   |
|   +------------------------+   +-------------------------+   |
|                                                               |
|   Interconnect: AXI4 128-bit wide                             |
|   Vector-NPU: Shared VRF (v0-v31)                             |
|                                                               |
+---------------------------------------------------------------+
```

### 2.3 v5.2 X++ — Enhanced Vector + Hawk (New)
```
+---------------------------------------------------------------+
|              ORCA v5.2 X++ SoC + Hawk NPU                     |
+---------------------------------------------------------------+
|                                                               |
|   +------------------------+   +-------------------------+   |
|   | ORCA v5.2 CPU          |   | Hawk NPU v5.2           |   |
|   | RV64GCV (VLEN=256)     |   | 8 TOPS INT8             |   |
|   | 4-issue OoO            |   | RVV-256 coupling        |   |
|   | Vector Unit (8 lanes)  |   | FMX2 4x 32x32 array     |   |
|   | 2.0 GHz                |   | Transformer hard-pipe   |   |
|   +------------------------+   +-------------------------+   |
|                                                               |
|   Interconnect: AXI4 256-bit wide                             |
|   New: Transformer Block acceleration in NPU                  |
|   Target: Edge LLM, BERT-base, ViT                            |
|                                                               |
+---------------------------------------------------------------+
```

---

## Part 3: ORCA 64-bit v6.x ZEN + AI Roadmap
### 3.1 v6.0 ZEN — Server-Class + Phoenix (Existing)
```
+---------------------------------------------------------------+
|              ORCA v6.0 ZEN SoC + Phoenix AI                   |
+---------------------------------------------------------------+
|                                                               |
|   +--------+  +--------+  +--------+  +--------+              |
|   | Core 0 |  | Core 1 |  | Core 2 |  | Core 3 |              |
|   |8-issue |  |8-issue |  |8-issue |  |8-issue |              |
|   |256 ROB |  |256 ROB |  |256 ROB |  |256 ROB |              |
|   |Sv48   |  |Sv48   |  |Sv48   |  |Sv48   |              |
|   +---+----+  +---+----+  +---+----+  +---+----+              |
|       |           |           |           |                   |
|   +---+-----------+-----------+---+       |                   |
|   |        L2$ 512K x4           |       |                   |
|   +--------------+---------------+       |                   |
|                  |                       |                   |
|   +--------------v---------------+  +----v----------------+   |
|   |         L3$ 8MB              |  | Phoenix AI Subsys   |   |
|   |      CHI Mesh 4x4            |  | TPE: 8 tiles        |   |
|   |      256-bit links           |  | AME: 16 blocks      |   |
|   +------------------------------+  | 16 TOPS INT8        |   |
|                                     | CHI.E/F 512-bit     |   |
|                                     +---------------------+   |
|                                                               |
|   Target: Server LLM, Qwen3-235B, DeepSeek-V3                 |
+---------------------------------------------------------------+
```

### 3.2 v6.1 ZEN-E — Edge Server + Phoenix-E (New)
```
+---------------------------------------------------------------+
|              ORCA v6.1 ZEN-E SoC + Phoenix-E                  |
+---------------------------------------------------------------+
|                                                               |
|   +--------+  +--------+                                       |
|   | Core 0 |  | Core 1 |                                       |
|   |8-issue |  |8-issue |                                       |
|   |256 ROB |  |256 ROB |                                       |
|   |Sv48   |  |Sv48   |                                       |
|   +---+----+  +---+----+                                       |
|       |           |                                            |
|   +---+-----------+---+                                        |
|   |    L2$ 512K x2    |                                        |
|   +--------+----------+                                        |
|            |                                                   |
|   +--------v----------+  +---------------------+               |
|   |    L3$ 4MB        |  | Phoenix-E AI        |               |
|   |    CHI 4x2        |  | TPE: 6 tiles        |               |
|   |    256-bit        |  | AME: 12 blocks      |               |
|   +-------------------+  | 12 TOPS INT8        |               |
|                          | CHI 256-bit         |               |
|                          | <8W                 |               |
|                          +---------------------+               |
|                                                               |
|   Target: Industrial gateway, smart NVR, medical imaging        |
+---------------------------------------------------------------+
```

### 3.3 v6.2 ZEN+ — Multi-Chip + Phoenix+ (New)
```
+---------------------------------------------------------------+
|              ORCA v6.2 ZEN+ Platform + Phoenix+               |
+---------------------------------------------------------------+
|                                                               |
|   +------------------------+  +------------------------+      |
|   |   Die 0 (Compute)      |  |   Die 1 (Compute)      |      |
|   |   ORCA v6.0 ZEN x4     |  |   ORCA v6.0 ZEN x4     |      |
|   |   Phoenix TPE+AME      |  |   Phoenix TPE+AME      |      |
|   |   16 TOPS              |  |   16 TOPS              |      |
|   +-----------+------------+  +-----------+------------+      |
|               |                           |                   |
|               +========= UCIe ============+                   |
|               |      256-bit D2D          |                   |
|               +===========================+                   |
|                                                               |
|   Total: 8 cores, 64 TOPS (CPU) + 32 TOPS (AI) = 96 TOPS     |
|   Package: 2.5D CoWoS-S                                       |
|   Target: Datacenter inference, 5G MEC, fleet AI              |
+---------------------------------------------------------------+
```

---

## Part 4: Unified Roadmap Timeline
### 2026 Q3-Q4 (Current)
| Product | Status | Milestone |
|:|:---|:---|
| ORCA 32-bit + Kestrel | 🟡 Planning | RTL design start |
| ORCA v5.0 X + Kestrel | ✅ Complete | FPGA proven (ZCU104) |
| ORCA v5.1 X+ + Falcon | ✅ Complete | Simulation ready |
| ORCA v5.2 X++ + Hawk | ✅ Complete | RTL ready, lint pending |
| ORCA v6.0 ZEN + Phoenix | ✅ Complete | Architecture frozen |
| ORCA v6.1 ZEN-E + Phoenix-E | ✅ Complete | RTL ready |
| ORCA v6.2 ZEN+ + Phoenix+ | ✅ Complete | RTL + UCIe TB ready |

### 2027 Q1-Q2
| Product | Milestone |
|:|:---|
| ORCA 32-bit + Kestrel | FPGA prototype (Arty A7) |
| ORCA v5.0 X + Kestrel | Silicon tapeout (22nm test chip) |
| ORCA v5.1 X+ + Falcon | FPGA prototype (VCK190) |
| ORCA v5.2 X++ + Hawk | Pre-silicon validation complete |
| ORCA v6.0 ZEN + Phoenix | FPGA emulation (Alveo U55C) |
| ORCA v6.1 ZEN-E + Phoenix-E | FPGA prototype (VCK190) |
| ORCA v6.2 ZEN+ + Phoenix+ | Interposer design complete |

### 2027 Q3-Q4
| Product | Milestone |
|:|:---|
| ORCA 32-bit + Kestrel | Silicon validation (22nm) |
| ORCA v5.0 X + Kestrel | Production samples |
| ORCA v5.1 X+ + Falcon | Silicon tapeout (12nm) |
| ORCA v5.2 X++ + Hawk | Silicon tapeout (7nm) |
| ORCA v6.0 ZEN + Phoenix | Pre-silicon signoff |
| ORCA v6.1 ZEN-E + Phoenix-E | Silicon tapeout (7nm) |
| ORCA v6.2 ZEN+ + Phoenix+ | CoWoS assembly + test |

### 2028
| Product | Milestone |
|:|:---|
| ORCA 32-bit + Kestrel | Mass production (IoT) |
| ORCA v5.0 X + Kestrel | EOL (replaced by v5.1) |
| ORCA v5.1 X+ + Falcon | Production (edge vision) |
| ORCA v5.2 X++ + Hawk | Production (edge AI server) |
| ORCA v6.0 ZEN + Phoenix | Production (datacenter) |
| ORCA v6.1 ZEN-E + Phoenix-E | Production (industrial) |
| ORCA v6.2 ZEN+ + Phoenix+ | Production (high-density DC) |

---

## Part 5: Software Ecosystem Roadmap
### Compiler Support
| Component | 32-bit | v5.x | v6.x | Status |
|:|:---|:---|:---|:---|
| GCC 14+ | rv32imc | rv64gcv | rv64gcv | ✅ Ready |
| LLVM 18+ | Planned | ✅ | ✅ | In development |
| OpenSBI | Planned | ✅ | ✅ | Ready |
| Linux 6.10+ | Planned | ✅ | ✅ | Ready |
| Zephyr RTOS | ✅ | Planned | — | Ready |
| FreeRTOS | ✅ | — | — | Ready |
| TensorFlow Lite Micro | ✅ | — | — | Ready |
| ONNX Runtime | — | ✅ | ✅ | Planned |
| PyTorch 2.0 | — | ✅ | ✅ | Planned |

### AI Framework Support
| Framework | Kestrel | Falcon | Hawk | Phoenix | Phoenix-E | Phoenix+ |
|:|:---:|:---:|:---:|:---:|:---:|:---:|
| TensorFlow Lite Micro | ✅ | ✅ | — | — | — | — |
| ONNX Runtime | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| PyTorch 2.0 | — | — | ✅ | ✅ | ✅ | ✅ |
| JAX | — | — | — | Planned | Planned | Planned |
| vLLM | — | — | — | Planned | Planned | Planned |

---

## Part 6: Competitive Positioning
### vs ARM Ethos / Mali
| Segment | ARM | ORCA | Advantage |
|:|:---|:---|:---|
| MCU NPU | Ethos-U55 (0.5T) | **Kestrel (1T)** | **2×** + open source |
| Edge NPU | Ethos-U65 (1T) | **Falcon (4T)** | **4×** + open source |
| Edge Server | — | **Hawk (8T)** | **Only ORCA** |
| Datacenter | Neoverse V2 | **Phoenix (16T)** | Comparable + open |
| Multi-Chip | — | **Phoenix+ (32T)** | **Only ORCA** |

### vs T-Head (Complete Matrix)
| Segment | T-Head | ORCA 32-bit | ORCA 64-bit v5.x | ORCA 64-bit v6.x |
|:|:---|:---|:---|:---|
| MCU (0-1T) | — | **32-bit + Kestrel** | — | — |
| Edge (1-4T) | C906 + NPU (0.5T) | — | **v5.0/v5.1** | — |
| Edge AI (4-8T) | Yeying 1520 (4T) | — | **v5.2 Hawk** | — |
| Edge Server (8-16T) | — | — | — | **v6.1 Phoenix-E** |
| Datacenter (16T+) | C950 (8T) | — | — | **v6.0 Phoenix** |
| High-Density DC (32T+) | — | — | — | **v6.2 Phoenix+** |

---

## Part 7: Key Metrics Summary
| Metric | 32-bit+Kestrel | v5.0+Kestrel | v5.1+Falcon | v5.2+Hawk | v6.0+Phoenix | v6.1+Phoenix-E | v6.2+Phoenix+ |
|:|:---|:---|:---|:---|:---|:---|:---|
| **CPU ISA** | RV32IMC | RV64GC | RV64GCV | RV64GCV | RV64GCV | RV64GCV | RV64GCV |
| **CPU Issue** | 1 | 4 | 4 | 4 | 8 | 8 | 8 |
| **CPU Freq** | 100MHz | 1.5GHz | 1.5GHz | 2.0GHz | 3.2GHz | 2.5GHz | 3.2GHz |
| **AI TOPS** | 1 | 1 | 4 | 8 | 16 | 12 | 32 |
| **AI Types** | INT8 | INT8/16 | INT8/16/FP16 | INT8/16/FP16/BF16 | INT8/16/FP16/BF16/FP32 | INT8/16/FP16/BF16/FP32 | INT8/16/FP16/BF16/FP32 |
| **Memory IF** | AXI4-Lite 32b | AXI4 64b | AXI4 128b | AXI4 256b | CHI 512b | CHI 256b | CHI 512b×2 + UCIe |
| **Process** | 22nm | 22nm | 12nm | 7nm | 5nm | 7nm | 5nm |
| **TDP** | <5mW | <2W | <5W | <8W | <100W | <40W | <200W |
| **Target** | IoT/TinyML | Edge gateway | Edge vision | Edge AI server | Datacenter | Industrial | High-density DC |
