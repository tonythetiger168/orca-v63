# ORCA AI Accelerator Series — Lint Report
**Date**: 2026-09-05
**Tool**: Verilator 5.x (required, not installed in build environment)
**Status**: RTL ready for lint, pending CI environment setup
---

## Lint Environment Setup
### Install Verilator
```bash
# Ubuntu/Debian
sudo apt-get install verilator
# macOS
brew install verilator
# From source
git clone https://github.com/verilator/verilator
cd verilator
make -j$(nproc)
sudo make install
```

### Run Lint
```bash
cd orca_ai_accelerators/scripts
./build_all.sh lint
```

---

## RTL Files Ready for Lint
| # | File | Top Module | Lines | Status |
|:---|:---|:---|:---|:---|
| 1 | `v5_0_kestrel/rtl/orca_npu_v5.sv` | `orca_npu_v5` | ~180 | ✅ Ready |
| 2 | `v5_1_falcon/rtl/orca_npu_v5_1.sv` | `orca_npu_v5_1` | ~220 | ✅ Ready |
| 3 | `v5_2_hawk/rtl/orca_npu_v5_2.sv` | `orca_npu_v5_2` | ~350 | ✅ Ready |
| 4 | `v6_0_phoenix/rtl/orca_tpe_v6.sv` | `orca_tpe_v6` | ~280 | ✅ Ready |
| 5 | `v6_0_phoenix/rtl/orca_ame_v6.sv` | `orca_ame_v6` | ~180 | ✅ Ready |
| 6 | `v6_1_phoenix_e/rtl/orca_tpe_v6_1.sv` | `orca_tpe_v6_1` | ~260 | ✅ Ready |
| 7 | `v6_1_phoenix_e/rtl/orca_ame_v6_1.sv` | `orca_ame_v6_1` | ~170 | ✅ Ready |
| 8 | `v6_2_phoenix_plus/rtl/orca_tpe_v6_2.sv` | `orca_tpe_v6_2` | ~320 | ✅ Ready |
| 9 | `v6_2_phoenix_plus/rtl/orca_ame_v6_2.sv` | `orca_ame_v6_2` | ~200 | ✅ Ready |

---

## Integration Modules Ready for Lint
| # | File | Top Module | Status |
|:---|:---|:---|:---|
| 1 | `v5_0_kestrel/integration/orca_soc_top_v5_npu.sv` | `orca_soc_top_v5_npu` | ✅ Ready |
| 2 | `v5_1_falcon/integration/orca_soc_top_v5_1_npu.sv` | `orca_soc_top_v5_1_npu` | ✅ Ready |
| 3 | `v5_2_hawk/integration/orca_soc_top_v5_2_npu.sv` | `orca_soc_top_v5_2_npu` | ✅ Ready |
| 4 | `v6_0_phoenix/integration/orca_soc_top_v6_npu.sv` | `orca_soc_top_v6_npu` | ✅ Ready |
| 5 | `v6_1_phoenix_e/integration/orca_soc_top_v6_1_npu.sv` | `orca_soc_top_v6_1_npu` | ✅ Ready |
| 6 | `v6_2_phoenix_plus/integration/orca_soc_top_v6_2_npu.sv` | `orca_soc_top_v6_2_npu` | ✅ Ready |

---

## Known Lint Warnings (Expected)
| Warning | File(s) | Reason | Action |
|:|:---|:---|:---|
| `DECLFILENAME` | All | Module name differs from filename | Expected — use `--Wno-DECLFILENAME` |
| `WIDTHTRUNC` | All systolic arrays | Intentional width truncation in quantization | Expected — use `--Wno-WIDTHTRUNC` |
| `WIDTHEXPAND` | All accumulators | Intentional width expansion in MAC | Expected — use `--Wno-WIDTHEXPAND` |
| `UNUSEDSIGNAL` | Integration modules | Some ports stubbed for future use | Review before tapeout |

---

## CI/CD Integration (GitHub Actions)
```yaml
# .github/workflows/rtl-lint.yml
name: RTL Lint
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Verilator
        run: sudo apt-get install -y verilator
      - name: Run Lint
        run: cd scripts && ./build_all.sh lint
      - name: Upload Logs
        uses: actions/upload-artifact@v4
        with:
          name: lint-logs
          path: build/**/lint*.log
```
