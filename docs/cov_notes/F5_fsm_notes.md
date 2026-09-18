# F5 域 FSM 覆蓋筆記 (ORCA v6.3.3.2)

工具: Verilator 5.006; 監控方式: 各 TB 內 `fsm_mon` initial 區塊於 posedge 比對狀態暫存器,
轉換寫入 `build/cov_final/<tb>/fsm.log`, python 彙總比對 RTL 合法集合。
arc 集合不含自轉 (monitor 只記值變化; 自轉 arc 屬維持態, 不計)。

## FSM 覆蓋結果 (全部 100%)

| 模組 | 狀態變數 | 合法狀態 | 覆蓋 | 合法 arc (非自轉) | 覆蓋 |
|---|---|---|---|---|---|
| ddr5_ctrl | `mst` (2b enum) | M_IDLE(0), M_ACT(1), M_RW(2) | 3/3 | IDLE→ACT, ACT→RW, RW→IDLE | 3/3 |
| pcie_gen6 | `lt` (3b enum) | LT_DETECT(0), LT_POLL(1), LT_CONFIG(2), LT_L0(3), LT_RECOVERY(4) | 5/5 | DETECT→POLL, POLL→CONFIG, CONFIG→L0, L0→RECOVERY, RECOVERY→DETECT | 5/5 |
| orca_chi_coh | `state` (coh_state_t) | COH_INVALID(0), COH_SHARED(1), COH_EXCLUSIVE(2), COH_MODIFIED(3) | 4/4 | 4×3=12 全雙向非自轉 | 12/12 |

## 不可達項與證明

1. **ddr5_ctrl `mst` 值 3 (2'b11)**: `mst` 為 2-bit enum, 僅三個列舉值;
   case 已對 M_IDLE/M_ACT/M_RW 完整覆蓋, `default` 分支為 defensive coding,
   無任何路徑可寫入 2'b11 (reset 寫 M_IDLE, 三個分支各寫列舉值)。
   → default 行已以 `/*verilator coverage_off*/` 豁免 (rtl/pad/ddr5_ctrl.sv line53-54)。

2. **pcie_gen6 `lt` 值 5/6/7**: 3-bit enum 僅五個列舉值, 同上 defensive default
   邏輯不可達 → 已豁免 (rtl/pad/pcie_gen6.sv line34-35)。

3. **orca_chi_coh COH_FORWARD(4)/COH_PENDING(5)**: coh_state_t 於 orca_pkg.sv
   定義 6 值 (MESI-F + transient), 但 orca_chi_coh RTL 的 case (line42-48)
   僅寫入 I/S/E/M 四值, snp 路徑 (line50) 亦僅寫 S;
   F/P 為 pkg 層保留值, 本模組無路徑可達 → 不列入合法狀態集。
   (state/snp_state 之 bit2 toggle 已由 TB poke-blitz 以 XMR 覆蓋。)

4. **ddr5_ctrl bank[4][4][4] 狀態機**: bank_state_t 7 值 (orac_pkg line302-308),
   但 RTL 僅 reset→BANK_IDLE(0) 與 ref_cnt 溢位→BANK_REFRESHING(6) 兩條寫入路徑
   (line44/49); ACTIVE/ACTIVATING/PRECHARGING/READING/WRITING 為 v6.3.4
   per-bank FR-FCFS 排程之保留狀態, 現行 stub 無路徑可達
   → bank 之 bit0/bit3 toggle 已豁免 (rtl/pad/ddr5_ctrl.sv line24-25)。

## 無 FSM 模組 (核對結論)

- **orca_bow_link**: 僅 `cnt` 4-bit 訓練計數器 (0→F 線性遞增, link_up=(cnt==4'hF)),
  無狀態列舉, 判定「無 FSM」(訓練序列已由 TB 完整走遍 cnt 0→F)。
- **orca_noc_router**: 純組合路由 (compute_route) + buffer 讀寫指標 (buf_wr_ptr/buf_rd_ptr),
  無狀態暫存器列舉, 判定「無 FSM」。
- **orca_noc_link**: 僅 `retry_v` 1-bit 旗標 (set/clear 兩態已由 retry TB 覆蓋),
  無狀態機, 判定「無 FSM」。
- **orca_flit_adapter**: 純組合 flit_t↔raw 轉換, 無時序元件, 判定「無 FSM」。
- **gpio_pad**: 純組合 pad 驅動, 判定「無 FSM」(F5 域 pad 檔, 一併核對)。
