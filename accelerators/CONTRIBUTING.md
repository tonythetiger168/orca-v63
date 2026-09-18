# Contributing to ORCA AI Accelerator Series
Thank you for your interest in contributing to ORCA! This document provides guidelines for contributing to the project.
## Code of Conduct
This project adheres to a code of conduct. By participating, you are expected to uphold this code:
- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Respect differing viewpoints
## How to Contribute
### Reporting Bugs
- Check if the bug has already been reported in [GitHub Issues](https://github.com/tonythetiger168/orca-ai-accelerators/issues)
- If not, open a new issue with:
- Clear title and description
- Steps to reproduce
- Expected vs actual behavior
- System information (OS, tool versions)
- Relevant code snippets or logs
### Suggesting Enhancements
- Open an issue with the `enhancement` label
- Describe the feature and its use case
- Explain why it would be useful to most users
### Pull Requests
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run lint checks (`cd scripts && ./build_all.sh lint`)
5. Commit with clear messages (`git commit -m 'Add feature X'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request
### Coding Standards
#### RTL (SystemVerilog)
- Follow [lowRISC Style Guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md)
- Use 2-space indentation
- Include header comments with module description
- Parameterize all configurable values
- Use `logic` instead of `reg`/`wire`
- Include `ifndef` guards in all files
#### Documentation
- Use Markdown format
- Keep line length under 100 characters
- Include diagrams where helpful (ASCII or Mermaid)
- Update relevant docs when adding features
## Development Setup
```bash
# Clone your fork
git clone https://github.com/tonythetiger168/orca-ai-accelerators.git
cd orca-ai-accelerators
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y verilator python3 python3-pip
# Run lint
cd scripts
./build_all.sh lint
# Run tests (when available)
cd tb
make sim
```

## Areas Needing Help
| Priority | Task | Required Skills | Difficulty |
|:|:---|:---|:---|
| 🔴 Critical | Verilator testbenches for v5.0-v6.2 | SystemVerilog, UVM | Hard |
| 🔴 Critical | LLVM/MLIR ORCA dialect implementation | C++, MLIR | Hard |
| 🟡 High | FPGA prototyping on ZCU104/VCK190 | Vivado, TCL | Medium |
| 🟡 High | Linux kernel driver for ORCA NPU | C, kernel APIs | Medium |
| 🟢 Medium | Python bindings for runtime | Python, Cython | Easy |
| 🟢 Medium | Documentation improvements | Technical writing | Easy |

## Questions?
- Open a [GitHub Discussion](https://github.com/tonythetiger168/orca-ai-accelerators/discussions)
- Email: orca-arch@example.org
## License
By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
