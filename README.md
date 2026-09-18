# ORCA v6.3 ZEN++

> The World's First 12-wide SMT-4 RISC-V + HBM3 AI Processor

[![CI](https://github.com/orca-semicon/orca-v63/actions/workflows/ci.yml/badge.svg)](https://github.com/orca-semicon/orca-v63/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Overview

ORCA v6.3 ZEN++ is a next-generation heterogeneous processor combining:
- **32-core RISC-V CPU** with 4-way SMT (128 threads)
- **4 AI Accelerator Tiles** delivering 512 TOPS INT8
- **HBM3 memory** with 9.8 TB/s bandwidth
- **< 50 ns CPU-AI co-processing latency**

## Key Specifications

| Component | Specification |
|-----------|--------------|
| CPU Cores | 32 (4 tiles x 8 cores) |
| SMT | 4-way per core (128 threads) |
| Issue Width | 12-wide dispatch / 16-wide retire |
| Target Clock | 3.8 GHz @ 3nm TSMC N3E |
| L3 Cache | 64 MB per tile + 3D V-Cache option |
| AI Compute | 512 TOPS INT8 / 256 TFLOPS BF16 |
| HBM3 | 96 GB total, 9.8 TB/s bandwidth |
| CPU-AI Latency | < 50 ns |
| Process | TSMC N3E + CoWoS-L |

## Project Structure

```
orca_v63/
├── rtl/                    # RTL source code
│   ├── cpu/               # CPU Tile (ZEN++)
│   ├── ai/                # AI Tile (ORCA-NPU v3)
│   ├── noc/               # Coherent mesh NoC
│   ├── soc/               # Top-level SoC
│   └── pad/               # IO / PHY interfaces
├── tb/                     # Testbench
│   ├── cpu_tile_tb/       # CPU tile UVM testbench
│   ├── ai_tile_tb/        # AI tile reference model
│   ├── sva/               # SystemVerilog Assertions
│   └── dpi/               # C++ DPI reference model
├── syn/                    # Synthesis constraints
├── scripts/                # Build & regression scripts
├── ci/                     # CI/CD configurations
├── docs/                   # Architecture specifications
└── charts/                 # Performance & market analysis
```

## Quick Start

### Prerequisites

- Synopsys VCS (U-2023.03 or later)
- Verilator (optional, for open-source lint)
- Xilinx Vivado (for FPGA prototyping)
- Python 3.8+ (for report generation)

### Build

```bash
# Generate file list
make filelist

# Compile with VCS
make vcs

# Run simulation
make sim

# Run lint checks
make lint

# FPGA synthesis
make fpga
```

### Run Tests

```bash
# Unit tests
make sim TEST=orca_cpu_alu_test
make sim TEST=orca_cpu_smt_test
make sim TEST=orca_cpu_exception_test

# Full regression
./scripts/run_regression.sh

# View waveforms
make wave
```

## Architecture

See [docs/arch_spec_v63.md](docs/arch_spec_v63.md) for the complete architecture specification.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

## Contact

- Website: https://orca-semicon.com
- Email: contact@orca-semicon.com

---

<p align="center">
  <sub>ORCA Semiconductor Inc. | Confidential - For Authorized Distribution Only</sub>
</p>
