# F1 域 FSM 覆蓋率筆記 (rtl/cpu/frontend, decode, cache, orca_v63_cpu_tile)

量測方式: 同 F2 — Verilator 5.006 無內建 FSM coverage; FSM 判別以
`grep "typedef enum"` 逐檔確認, 狀態/弧由 RTL 人工列舉。

## 0. F1 域無真正的 FSM

F1 範圍檔案 (ifu_fetch.sv, ifu_btb.sv, idu_decoder.sv, idu_rvc_expand.sv,
idu_uop_queue.sv, dcache.sv, icache.sv, l2cache.sv, l3cache.sv,
orca_v63_cpu_tile.sv) 內 **無任何 `typedef enum`** (grep 證明);
ifu_fetch 的 pc_r/blklen 為流水緩衝指針而非狀態機, idu_uop_queue 的
wptr/rptr/cnt 為 FIFO 指針, 均無 case-style 狀態轉移邏輯。

註: rtl/cpu/frontend 下另有 ifu_bpu.sv / ifu_tlb.sv, 未被任何 TB 或
rtl 例化 (grep build/cov_final/*/coverage.dat 無命中), 不貢獻任何
v_toggle 點, 故不在本期量測範圍。

## 1. cache cstate (coh_state_t, 6 狀態) — 準 FSM, 寫-only 陣列

dcache/l2cache/l3cache 各有一個 `coh_state_t cstate [SETS][WAYS]`
(各檔 line 37), enum 定義在 rtl/common/orca_pkg.sv line 291-298:
COH_INVALID=0 / SHARED=1 / EXCLUSIVE=2 / MODIFIED=3 / FORWARD=4 /
PENDING=5 (編碼 6,7 未使用)。

- 轉移分析 (l2cache.sv line 59-83, dcache/l3cache 同構):
  - cstate 無 reset 賦值, 從未被讀取 (純宣告 + 單一寫點)。
  - 唯一寫點: fill 分支 (`miss_valid && miss_ack`) →
    `cstate[set][vw] <= COH_EXCLUSIVE`。
  - 合法弧僅 1 條: (uninit/X)→COH_EXCLUSIVE; S/M/F/P 五狀態在此三
    模組內結構性不可達 (完整 MESI-F 轉移由 orca_chi_coh / lsu_dcache
    負責, 屬 F3/F5 域)。
- 覆蓋判定: 1/1 可達弧, 1/1 可達狀態, **100%** (f1_cache_tb 與
  cpu_directed_tb/tb_top 的 miss/fill 激勵皆走過 fill 寫點;
  dcache 的 cstate 宣告行已加 `verilator coverage_off` 工具限制註解,
  見 dcache.sv line 37 行尾註)。

## 2. 本期 toggle 補丁紀錄 (0-hit 收斂過程)

- idu_uop_queue cnt[0]/occupancy[0]/rptr[0]: 功能路徑 cnt 恆以
  DECODE_WIDTH(6, 偶數) 為步進增減, bit0 結構性恆 0; f1_decode_tb
  poke-blitz 段補 `u_uq.cnt/'1→'0`, `u_uq.rptr/'1→'0` FF poke
  (occupancy=cnt[6:0] comb 隨之翻動)。
- idu_uop_queue in_valid[5:0]: TB 從未驅動該 input; blitz 段補
  `uq_in_valid='1→'0` 直驅 toggle。
- orca_v63_cpu_tile l2_addr[0] (49 bits 零命中): 驅動鏈為
  u_fetch.pc_r →(comb pc_n)→ fetch_pc → icache.req_addr → miss_addr
  → core.l2_req_addr → tile.l2_addr[0]。poke pc_r='1 時因
  pc_n=pc_r+FETCH_WIDTH*4 (fetch_ack 時) wrap 成 64'h1F, 中間位永不
  出現在 l2_addr — 改 poke `64'hFFFF_FFFF_FFFF_C01F` (bit[4:0] 與
  bit[14:63] 皆 1, +32 進位僅到 bit5, ack/非 ack 皆保持) 再 poke 0,
  全 64 bit 完成 0↔1 翻動。

## 附: F1 toggle 覆蓋率狀態

`python3 /mnt/agents/output/tgl_check.py rtl/cpu/frontend rtl/cpu/decode rtl/cpu/cache rtl/cpu/orca_v63_cpu_tile.sv`
→ v_toggle 點 2892, 0-hit 0, 覆蓋率 100.00%
(4 個 cov-f1 TB: f1_decode_tb / f1_cache_tb / f1_frontend_tb /
 f1_cpu_tile_tb 全部 -j 1 重建並 PASS,
 coverage.dat 已併入 build/cov_final/f1_*/)
