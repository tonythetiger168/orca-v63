# ORCA AI Accelerator Series + CPU Ecosystem
<p align="center">&nbsp;&nbsp;<b>Open RISC-V Compute Architecture — AI Accelerator & CPU Series</b><br/>
&nbsp;&nbsp;<a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License"></a>
&nbsp;&nbsp;<a href="#"><img src="https://img.shields.io/badge/RTL-SystemVerilog-green.svg" alt="RTL"></a>
&nbsp;&nbsp;<a href="#"><img src="https://img.shields.io/badge/ISA-RISC--V%20RVV%201.0-orange.svg" alt="ISA"></a>
&nbsp;&nbsp;<a href="#"><img src="https://img.shields.io/badge/Process-22nm%20to%205nm-purple.svg" alt="Process"></a>
&nbsp;&nbsp;<a href="#"><img src="https://img.shields.io/badge/CI-GitHub%20Actions-yellow.svg" alt="CI"></a>
</p>

---

## Table of Contents
- [Overview](#overview)
- [Why ORCA](#why-orca)
- [Product Line](#product-line)
  - [AI Accelerators](#ai-accelerators)
  - [CPU Cores](#cpu-cores)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [Architecture Highlights](#architecture-highlights)
- [Software Stack](#software-stack)
- [Performance Comparison](#performance-comparison)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)
---

## Overview
ORCA is a **fully open-source** family of RISC-V processors and AI Neural Processing Units (NPUs). Spanning from **ultra-low-power 32-bit MCUs** to **high-performance 64-bit server chips** with **32 TOPS AI inference**, ORCA provides a unified programming model with **zero vendor lock-in**.
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
+-----------------------------------------------------------------------+
```

---

## Why ORCA
| Feature | ORCA | Typical Vendor IP |
|:---|:---|:---|
| **License** | Apache 2.0 | Proprietary / NDAs |
| **Cost** | Free | $100K-$5M+ per license |
| **Customization** | Full RTL access | Black box |
| **Toolchain** | Standard LLVM/GCC | Vendor-locked |
| **Migration** | Seamless across generations | Re-design required |
| **Community** | Open contributions | Vendor-only |

---

## Product Line
### AI Accelerators
| Generation | Codename | Peak INT8 | Process | Target | Key Feature |
|:---|:---|:---|:---|:---|:---|
| v5.0 X | **Kestrel** | 1 TOPS | 22nm / 1GHz | Edge IoT | Ultra-lightweight, <150mW |
| v5.1 X+ | **Falcon** | 4 TOPS | 12nm / 1.5GHz | Edge Vision | RVV 1.0 + FMX dual systolic |
| v5.2 X++ | **Hawk** | 8 TOPS | 7nm / 2.0GHz | Edge AI Server | Transformer hard-acceleration |
| v6.0 ZEN | **Phoenix** | 16 TOPS | 5nm / 3.2GHz | Datacenter | TPE + AME sparse engine |
| v6.1 ZEN | **Phoenix-E** | 12 TOPS | 7nm / 2.5GHz | Edge Server | Phoenix downscaled, <8W |
| v6.2 ZEN | **Phoenix+** | 32 TOPS | 5nm x2 / 3.2GHz | High-Density DC | Dual-die UCIe chiplet |

### CPU Cores
| Generation | ISA | Pipeline | ROB | MMU | Frequency | Target |
|:---|:---|:---|:---|:---|:---|:---|
| v3.0 Base | RV32I/RV64I | 2/3-stage | — | — | 16-100MHz | MCU/TinyML |
| v5.0 X | RV64GC | 4-issue OoO | 128 | Sv39 | 1.5GHz | Edge Gateway |
| v5.1 X+ | RV64GCV | 4-issue OoO | 128 | Sv39 | 1.5GHz | Edge Vision |
| v6.0 ZEN | RV64GCV | 8-issue OoO | 256 | Sv48 | 3.2GHz | Datacenter |
| v6.1 ZEN-E | RV64GCV | 8-issue OoO | 256 | Sv48 | 2.5GHz | Edge Server |
| v6.2 ZEN+ | RV64GCV | 8-issue OoO | 256 | Sv48 | 3.2GHz | High-Density DC |
| v6.3 | RV64GCV | TBD | TBD | TBD | TBD | Future |

---

## Quick Start
```bash
# Clone the repository
git clone https://github.com/tonythetiger168/orca-ai-accelerators.git
cd orca-ai-accelerators
# Run lint checks (requires Verilator)
cd scripts
./build_all.sh lint
# View architecture docs
ls docs/
# Explore RTL
ls cpu/v6_0/rtl/
ls v6_0_phoenix/rtl/
```

---

## Repository Structure
```
orca-ai-accelerators/
├── cpu/                          # RISC-V CPU Cores
│   ├── v3_0/                   # Base 32/64-bit CPU (2/3-stage)
│   │   ├── rtl/                # orca_core.sv, orca_alu.sv...
│   │   ├── docs/               # Architecture docs
│   │   └── uvm/                # UVM testbench
│   ├── pre_research/           # Pre-research phase
│   │   ├── docs/               # Design specifications
│   │   ├── p3/                 # Performance optimization
│   │   ├── p4/                 # Power optimization
│   │   ├── pd/                 # Physical design
│   │   ├── formal/             # Formal verification
│   │   ├── fpga/               # FPGA prototyping
│   │   ├── fpu/                # Floating point unit
│   │   ├── rv64/               # 64-bit extension
│   │   ├── security/           # PMP, TrustZone
│   │   ├── software/           # HAL, boot, linker
│   │   ├── testchip/           # Testchip bringup
│   │   ├── toolchain/          # GCC, LLVM, OpenOCD
│   │   └── risk_mgmt/          # Competitive analysis
│   ├── v5_0/                   # 4-issue OoO, RV64GC
│   ├── v5_1/                   # RV64GCV, VLEN=128
│   ├── v6_0/                   # 8-issue OoO, CHI Mesh
│   ├── v6_1/                   # Edge server variant
│   ├── v6_2/                   # Dual-die server
│   └── v6_3/                   # Future roadmap
│
├── v5_0_kestrel/             # AI NPU: 1 TOPS
│   ├── rtl/orca_npu_v5.sv
│   ├── docs/Kestrel_Architecture.md
│   └── integration/orca_soc_top_v5_npu.sv
├── v5_1_falcon/              # AI NPU: 4 TOPS
│   ├── rtl/orca_npu_v5_1.sv
│   ├── docs/Falcon_Architecture.md
│   └── integration/orca_soc_top_v5_1_npu.sv
├── v5_2_hawk/                # AI NPU: 8 TOPS
│   ├── rtl/orca_npu_v5_2.sv
│   ├── docs/Hawk_Architecture.md
│   └── integration/orca_soc_top_v5_2_npu.sv
├── v6_0_phoenix/             # AI NPU: 16 TOPS
│   ├── rtl/orca_tpe_v6.sv
│   ├── rtl/orca_ame_v6.sv
│   ├── docs/Phoenix_Architecture.md
│   └── integration/orca_soc_top_v6_npu.sv
├── v6_1_phoenix_e/           # AI NPU: 12 TOPS
│   ├── rtl/orca_tpe_v6_1.sv
│   ├── rtl/orca_ame_v6_1.sv
│   ├── docs/Phoenix_E_Architecture.md
│   └── integration/orca_soc_top_v6_1_npu.sv
├── v6_2_phoenix_plus/        # AI NPU: 32 TOPS
│   ├── rtl/orca_tpe_v6_2.sv
│   ├── rtl/orca_ame_v6_2.sv
│   ├── docs/Phoenix_Plus_Architecture.md
│   └── integration/orca_soc_top_v6_2_npu.sv
├── docs/                     # Documentation
│   ├── ORCA_AI_Series_Overview.md
│   ├── ORCA_Unified_Roadmap_2026_2028.md
│   ├── THead_vs_ORCA_AI_Comparison.md
│   ├── Software_Stack.md
│   ├── Lint_Report.md
│   ├── compiler/
│   │   └── LLVM_MLIR_Backend.md
│   └── physical_design/
│       └── Phoenix_Plus_CoWoS_Package.md
├── tb/                       # Testbenches
│   └── ucie/
│       └── tb_ucie_d2d.sv
├── scripts/                  # Build & verification
│   └── build_all.sh
└── .github/                  # CI/CD workflows
    └── workflows/
        ├── rtl-lint.yml
        ├── cpu-ci.yml
        ├── docs-check.yml
        └── code-quality.yml
```

---

## Architecture Highlights
### v5.2 Hawk — Transformer Block Hard-Acceleration
Hawk introduces the world's first open-source **Transformer Block hard-pipeline** for edge AI, enabling BERT/GPT-2 inference at the edge.
```
Input -> LayerNorm -> Q/K/V MatMul -> Softmax -> V MatMul -> FF -> Output         +-------------- Hardware Pipeline --------------+
```

### v6.2 Phoenix+ — UCIe Chiplet Scaling
Phoenix+ achieves 32 TOPS by connecting two Phoenix dies via **UCIe (Universal Chiplet Interconnect Express)**, enabling linear performance scaling without silicon redesign.
| Metric | Single Die (v6.0) | Dual Die (v6.2) | Scaling |
|:|:---|:---|:---|
| TOPS | 16 | **32** | **2.0x** |
| TDP | <15W | **<30W** | **2.0x** |
| Area | 8.5 mm2 | **2 x 8.5 mm2** | **2.0x** |

---

## Software Stack
| Layer | Technology | Status |
|:|:---|:---|
| **Frameworks** | PyTorch 2.0, TensorFlow, ONNX Runtime | Planned |
| **Compiler** | LLVM 18 + MLIR + ORCA dialects | In Development |
| **Runtime** | libphoenix.so, libphoenix_plus.so | Planned |
| **Drivers** | Linux kernel module, OpenSBI | Planned |
| **Simulation** | Verilator, QEMU | Ready |

---

## Performance Comparison
### vs T-Head (Alibaba Pingtouge)
| Product | T-Head | ORCA | Advantage |
|:|:---|:---|:---|
| Embedded AI | C906 + NPU (0.5T) | **Kestrel (1T)** | **2x** |
| Edge Vision | Yeying 1520 (4T) | **Falcon (4T)** | Equal + Open Source |
| Edge Server | — | **Phoenix-E (12T)** | **Only ORCA** |
| Datacenter | C950 (8T) | **Phoenix (16T)** | **2x** |
| Multi-Chip | — | **Phoenix+ (32T)** | **Only ORCA** |

---

## Documentation
### AI Accelerator Docs
- [Series Overview](docs/ORCA_AI_Series_Overview.md) — Full product line comparison
- [Unified Roadmap 2026-2028](docs/ORCA_Unified_Roadmap_2026_2028.md) — 32-bit & 64-bit CPU + AI roadmap
- [Kestrel Architecture](v5_0_kestrel/docs/Kestrel_Architecture.md) — 1 TOPS edge NPU
- [Falcon Architecture](v5_1_falcon/docs/Falcon_Architecture.md) — 4 TOPS vector NPU
- [Hawk Architecture](v5_2_hawk/docs/Hawk_Architecture.md) — 8 TOPS Transformer NPU
- [Phoenix Architecture](v6_0_phoenix/docs/Phoenix_Architecture.md) — 16 TOPS flagship
- [Phoenix-E Architecture](v6_1_phoenix_e/docs/Phoenix_E_Architecture.md) — 12 TOPS edge server
- [Phoenix+ Architecture](v6_2_phoenix_plus/docs/Phoenix_Plus_Architecture.md) — 32 TOPS dual-die
### CPU Docs
- [v5.0 X Architecture](cpu/v5_0/docs/architecture.md) — 4-issue OoO CPU
- [v6.0 ZEN README](cpu/v6_0/README.md) — 8-issue OoO + CHI Mesh
- [T-Head Comparison](cpu/common/docs/THead_vs_ORCA_Comparison_Report.md) — Competitive analysis
### Compiler & Physical Design
- [Compiler Backend](docs/compiler/LLVM_MLIR_Backend.md) — LLVM/MLIR integration
- [CoWoS Package](docs/physical_design/Phoenix_Plus_CoWoS_Package.md) — 2.5D chiplet design
---

## Contributing
We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
### Areas Needing Help
| Priority | Task | Skills |
|:|:---|:---|
| 🔴 High | Verilator testbenches for all generations | SystemVerilog, UVM |
| 🔴 High | LLVM/MLIR dialect implementation | C++, MLIR |
| 🟡 Medium | FPGA prototyping (ZCU104, VCK190) | Vivado, HLS |
| 🟡 Medium | Linux kernel driver | C, kernel dev |
| 🟢 Low | Documentation translation | Technical writing |

---

## License
ORCA is licensed under the **Apache License 2.0**.
See [LICENSE](LICENSE) for full terms.
```
Copyright 2026 ORCA Architecture Team
Licensed under the Apache License, Version 2.0 (the 'License');
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
```

---

## Acknowledgments
- RISC-V International Foundation for the open ISA standard
- LLVM Project for the compiler infrastructure
- Verilator community for open-source simulation
- UCIe Consortium for chiplet interconnect standard
---

## Contact
- 💬 Discussions: [GitHub Discussions](https://github.com/tonythetiger168/orca-ai-accelerators/discussions)
- 🐛 Issues: [GitHub Issues](https://github.com/tonythetiger168/orca-ai-accelerators/issues)
