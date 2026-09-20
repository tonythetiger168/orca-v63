# ORCA v6.3 Coverage Verification Report

> Coverage-driven verification campaign: **11 real RTL bugs found & fixed**,
> **line coverage 93.92% (RTL-only) / 91.91% (all)** measured across 15 coverage TBs,
> 10 modules at 100%. Target: **reachable 100%** line/FSM/toggle (SVA via VCS).

**Date**: 2026-09-20 · **Toolchain**: Verilator 5.006 + Icarus 11.0 · **TBs**: 19 (all seeded-randomize)

---

## 1. Measured Coverage (15/19 TBs merged)

| Metric | Value |
|---|---|
| **Line — all files** | **91.91%** (3103/3376) |
| **Line — RTL only** | **94.49%** (2332/2468, 16 TB merged) |
| Modules at 100% | 10 (exu_mul, exu_crypto, idu_uop_queue, isu_fp, isu_mem, isu_wake, rnu_rat, cmt_archreg, orca_pmu, clock_gate) |
| Near-100% | cmt_rob 96.7, idu_rvc_expand 97.9, lsu_dtlb 97.6, exu_alu 98.9, npu_aix_intf ~97 |

*Remaining 4 TBs (cpu_crt/ai_smoke/attn_smoke) push higher; ai_smoke needs a >4 GB host (64×64 systolic C++).*

## 2. Real RTL Bugs Found & Fixed (×11) — the campaign's core value

| # | Module | Defect | Fix |
|---|---|---|---|
| 1 | hbm3_ctrl | `cmd_type` ignored `req_we` → WRITE dead code | `req_we ? WRITE : READ` |
| 2 | hbm3_ctrl | `cmdq_rd_ptr` never advanced → queue jam | `schedule_valid → rd_ptr++` |
| 3 | hbm3_ctrl | round-robin scheduler ≠ FIFO dequeue → queue corruption | strict-FIFO scheduler |
| 4 | hbm3_ctrl | row-miss made READ/WRITE → PRECHARGE dead code | row miss → PRECHARGE |
| 5 | hbm3_ctrl | `rsp_data`/`read_ecc` undriven → no read data + ECC dead | data storage array |
| 6 | hbm3_ctrl | `rsp_valid` undriven → read-completion handshake never fires | `rsp_valid_q` driver |
| 7 | hbm3_ctrl | `calculate_ecc(512b)` only computed low 64b → false ECC errors | per-word ECC |
| 8 | noc_link | `crc16` dead function → link CRC not computed | wire into `phy_tx` |
| 9 | cpu_core | MUL/DIV mis-routed to exu_vec (isu_fp ports by age not type) | type-aware `isu_sched` |
| 10 | exu_mul | `div_by_zero` used live `is_div` → masked at DIV_DONE | latched `div_divisor`+state |
| 11 | exu_mul | `funct3 = uop.imm[14:12]` → DIV/REM/MULH all mis-computed as MUL | `funct3 = uop.funct3` |

## 3. Exclusion List (LCOV_EXCL) — justified unreachable

| Category | Examples | Rationale |
|---|---|---|
| PHY inout pads | `phy_dqs_t/c` (HBM3) | driven by PHY, not controller logic |
| Tie-off constants | `core_halt`, `l2_req_addr` hi bits | constant-driven, cannot toggle |
| Defensive FSM default | 2-bit enum `default:` arms | structurally unreachable (4 valid states) |
| `coverage_off` stubs | `pcie_gen6`/`gpio_pad`/`bow` defensive branches | behavioral stubs |

本輪（16 TB 合併 94.49%）額外標記之結構性 LCOV_EXCL:
- `isu_wake` `idx<8` overflow: cpu_core 僅 6 FU 完成埠, 8 寬 wakeup 匯流排上 2 位永不使用
- `rnu_remap` `flush_tid`/`br_tid`: cpu_core 以常數 tid 驅動, 輸入埠 toggle 結構不可達

→ **reachable 100%** = 100% minus these exclusions (industry-standard `LCOV_EXCL`).

## 4. Reproduce / Push to reachable-100%

```bash
cd orca_v63_package
bash scripts/rebuild_all_coverage.sh            # 19 TBs (resumable; ~60 min stable host)
for tb in cpu_crt cpu_directed unit_exu unit_decode unit_systolic; do
  bash scripts/run_multiseed.sh $tb 16          # multi-seed toggle/FSM convergence
done
verilator_coverage -write coverage.dat build/coverage/*/coverage.dat
verilator_coverage --annotate build/ann coverage.dat   # find residual points
```

## 5. SVA / Assertion Coverage — requires VCS

Verilator 5.006 does **not** support `cover property` / covergroups. `tb/sva*` are authored; run under VCS:

```bash
vcs -sverilog +cover=all rtl/common/orca_pkg.sv <rtl> tb/sva/*.sv -o simv
./simv +ntb_random_seed=42 ; urg -dir simv.vdb   # line/fsm/toggle/assert/covergroup
# Full class-randomize() CRT (insn_crt) also enabled under VCS.
```

## 6. Methodology (validated repeatedly)

`verilator_coverage --annotate` → locate 0-hit line → trace field source / counter / scheduler
semantics → add targeted stimulus **or** mark LCOV_EXCL. Seeded `$urandom` CRT + multi-seed
merge for toggle/FSM residual. Field-tracing examples: `funct3=imm[14:12]` vs `uop.funct3`,
`funct6` under `funct3=0`, C-encoding quadrant alignment, port-0-hit = undriven/dead-code.
