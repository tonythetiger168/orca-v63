# F2 域 FSM 覆蓋率筆記 (rtl/cpu/execution, 1 個 FSM)

量測方式: Verilator 5.006 無內建 FSM coverage, 於 TB 加 `fsm_mon`
initial 區塊, 在 posedge clk (#1 後) 監控狀態暫存器, 首次出現的
(prev, cur) 弧 (含 self-arc) 以 `FSM_ID prev next` 格式附加寫入
run 目錄的 fsm.log。
fsm.log: /mnt/agents/output/orca_v63_package/build/cov_final/f2_mul/fsm.log

F2 域 (rtl/cpu/execution/*.sv) 僅此一個 FSM (grep `typedef enum` 證明,
其餘 alu/bru/crypto/fpu/vec/prf 皆為純管線, 無狀態機)。

## 1. exu_mul div_state (2-bit enum, 3 狀態) — TB: exu_mul_cov_tb
- 狀態: DIV_IDLE=0, DIV_RUNNING=1, DIV_DONE=2 (rtl/cpu/execution/exu_mul.sv
  line 163-167); 編碼值 3 未使用, 結構性不可達 (case 無 default arm,
  除 reset 外三個 arm 皆只可能轉向已定義狀態)。
- 合法弧 5 (由 RTL case 項列舉, line 195-227):
  - 0→0 (DIV_IDLE self: 無 div/rem uop 時維持)
  - 0→1 (DIV_IDLE→DIV_RUNNING: uop_valid && uop_ready && (is_div||is_rem))
  - 1→1 (DIV_RUNNING self: 64 次 restoring 迭代, div_counter<63)
  - 1→2 (DIV_RUNNING→DIV_DONE: div_counter>=63)
  - 2→0 (DIV_DONE→DIV_IDLE: 無條件返回)
- 結果: **5/5 弧, 3/3 狀態, 100%** (fsm.log: `0 0 / 0 1 / 1 1 / 1 2 / 2 0`)
- 激勵來源: TB 功能段共發 12 筆 DIV/DIVU/REM/REMU (含 2 筆 div-by-zero
  exception 路徑), 每筆皆完整走 IDLE→RUNNING→(63 self)→DONE→IDLE;
  無任何 poke/force 產生假弧 (poke-blitz 段不觸碰 div_state)。
- 備註: 同檔 div_quotient 為 dead 宣告 (僅 reset 寫 0, 從未被讀取),
  已於 RTL 加 `/*verilator coverage_off/on*/` 註解豁免其 toggle 點,
  未改任何邏輯 (exu_mul.sv line 171-172)。

## 附: F2 toggle 覆蓋率狀態
`python3 /mnt/agents/output/tgl_check.py rtl/cpu/execution`
→ v_toggle 點 4622, 0-hit 0, 覆蓋率 100.00%
(6 個 cov-f2 TB: alu/mul/vec/fpu/bru_crypto/prf 全部 PASS,
 coverage.dat 已併入 build/cov_final/f2_*/)
