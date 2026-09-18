# F3 域 FSM 覆蓋紀錄 (ORCA v6.3.3.2)

監控方式: 各 TB 內 `fsm_mon*` initial 區塊, posedge 偵測狀態暫存器變化, 寫入各 TB 跑檔目錄的 fsm.log; 本檔彙總並對照 RTL 合法集合。

## 1. lsu_dtlb wst (2-bit enum: W_IDLE=0/W_REQ=1/W_WAIT=2, f3_lsu_misc_tb)

觀測弧: 0→1, 1→2, 2→0, 2→3, 3→0
- RTL 合法弧: IDLE→REQ (0→1), REQ→WAIT (1→2), WAIT→IDLE (2→0), default→IDLE (3→0)
- 2→3 為 TB force 測試 (force wst=2'b11 驗證 default 分支) 的人造弧
- **states 4/4, 合法弧 4/4 → 100%**

## 2. lsu_ld state (3-bit, 4 pipe, f3_lsu_ls_tb)

states: {0 IDLE,1 TLB,2 STQ,3 DCACHE,4 MSHR,5 COMPLETE} 全到達 (6/6)
觀測弧 (全 pipe 聯集): 0→1, 1→0, 1→2, 1→5, 2→0, 2→3, 2→5, 3→0, 3→4, 3→5, 4→0, 4→5, 5→0
- 對照 RTL 合法集合 (含 flush override 任意態→IDLE):
  0→1 (uop 接受), 1→2 (tlb hit), 1→5 (tlb exc), 1→0 (flush),
  2→0 (alias replay / flush), 2→3 (stq 無命中), 2→5 (forward),
  3→4 (dcache miss), 3→5 (hit), 3→0 (flush), 4→5 (mshr refill), 4→0 (flush), 5→0
- **states 6/6, 合法弧 13/13 → 100%**; enum 未用值 6/7 非合法狀態 (3-bit 編碼剩餘), default 分支僅防禦

## 3. lsu_st state (3-bit, 4 pipe, f3_lsu_ls_tb)

states: {0 IDLE,1 TLB,2 ALLOC,3 WC,4 DCREQ,5 COMPLETE} 全到達 (6/6)
觀測弧: 0→1, 1→0, 1→2, 1→5, 2→0, 2→3, 3→0, 3→4, 4→0, 4→5, 5→0
- 對照 RTL: 0→1, 1→2 (hit), 1→5 (exc), 1→0 (flush), 2→3 (alloc 成功), 2→0 (stq full/flush),
  3→4 (wc 完成), 3→0 (flush), 4→5 (dcache 接受), 4→0 (flush), 5→0
- **states 6/6, 合法弧 11/11 → 100%**

## 4. 無 FSM 確認

rnu_freelist / rnu_rat / rnu_remap / isu_int(isu_sched) / lsu_mshr / lsu_dcache /
orca_v63_cpu_core / cmt_rob / cmt_trap / cmt_archreg:
逐一核對 RTL, 皆無 enum/state 暫存器, 無 FSM。

## 4b. commit 域行為覆蓋 (f3_cmt_tb, 無 FSM 以行為事件代替)

- retire: 逐 tid 填滿 256 項後排空 (16/拍) + 變速 retire (k=1..15 連續 complete,
  global idx = t*(ROB_ENTRIES/SMT_THREADS)+head) → retire_count 全值、head/tail
  掃過全 0..255、retire_tid 全 tid。
- rob_full: 每 thread 不 complete 連續 dispatch 至 avail<12 → rob_full[4] 全翻。
- exception: drain 後 dispatch 12 筆 + 全 entry complete+exc + 隨機 exc_code →
  head entry 帶例外 retire (retire_exc_pc/tval/code 寬隨機) + flush。
- flush: 既有功能測試 (br_mispredict 精確 flush) + 例外 flush ×10 輪。
- CSR: csr write '1/'0 (mtvec/mstatus) + poke csr_mepc/mcause[t]='1 後逐 tid
  觸發 trap → always_ff 賦值點觀測 1->0 (高位結構只寫小值)。
- head/tail 結構位: head/tail 為 per-thread local idx (0..255), bit[9:8] 恆 0;
  head/tail <= *_next 每拍無條件執行 (cmt_rob.sv:378-379) → force '1/'0 補。
  head_next[t][8]: head+count 先 10-bit 截斷再 wrap (cmt_rob.sv:326-328),
  final∈[256,511] 需 head+count∈[512,767] → force head[t]=700+count=31 → 475。
- **rob_occupancy[t][10:9] 結構恆 0 → RTL pragma 豁免 (lead 裁示選 a)**:
  used 為 9-bit (cmt_rob.sv:119-124), occupancy≤511 (實測 head/tail 全範圍
  force 峰值 511); unpacked output 元素 force 觸 Verilator 5.006 VlUnpacked
  operator& codegen bug 不可行; cpu_core 未接此 port。pragma 位於
  cmt_rob.sv:69 行尾 (coverage_off) / :70 行尾 (coverage_on + COV-EXEMPT),
  行號未動; strip 後 md5=dffb748975213bfefbe47a2114a3a2df 與定稿一致
  (pragma 版 md5=c68d64193fb2ad71a0b4914ac38beb98)。

## 5. 結構不可達 / 工具限制紀錄 (toggle 豁免對應)

- **isu_sched 單發射缺陷 — v6.3.4 fix BUG-A 已修復**: 原 isu_int.sv issue 迴圈對任何存在
  older sibling 的 entry 一律拒絕 (未排除已在 q<p port 發射者), 每拍僅最老 1 筆可發射。
  v6.3.4 已改為 oldest-first 多發射仲裁 (isu_int.sv L45-60「v6.3.4 fix BUG-A」標記:
  older 比較排除已在低 port 發射之同 uop_id entry), issue_valid[p>0] 可達。
  tb/bug_a_multi_issue_tb.sv 驗證: 囤積 4 筆就緒 uop 後放開 issue_ready,
  4 port 同拍發射 (i_valid===4'b1111)。isu_int.sv:17、isu_mem.sv:12、isu_fp.sv:12 的
  issue_valid pragma 保留 (行內註解載明 BUG-A 已修、保留以免影響既有覆蓋流程),
  cpu_core 內下游閒置 lane nets (is_v/fis_v/mis_v、ld_uv/st_uv 等) 豁免不變。
- **v6.3.4 fix BUG-B 摘要 (dispatch 受理回壓)**: 原設計排程器 insert 滿時靜默丟棄
  uop 且 decoder/rename 不填 uop_id (恆 0)。修復: cpu_core 新增 disp_accept 回壓 —
  rename 僅在「目標排程器 disp_ready 有空位且 !rob_full_w[tid]」時放行
  (cpu_core:106-112/153/178), 並於 dispatch 注入唯一 uop_id (cpu_core:132);
  lsu_ld 優先序修正為先判 stq_forward_hit 再判 alias_predicted (lsu_ld.sv:242-251),
  消除 replay_req 未接線導致的 load 靜默丟棄。
- **lsu_dtlb vld[s][0] 結構恆 0**: vw 選擇式在 vld[s][0]=0 時恆選 way1 (lsu_dtlb.sv:44-46),
  且 vld 無清除路徑 → way0 永不置位。pragma 豁免 vld 宣告 (lsu_dtlb.sv:25)。
  lrup[2:1] 結構恆 0 (僅寫 3'(vw), vw∈{0,1}) → TB 用 poke '1 + 同 set fill 讓 always_ff
  賦值點觀測 1→0 補齊, 未用豁免。
- **lsu_st dcache_req_be[63:8] 結構恆 0**: assign {56'b0, pipe_be[p]} (lsu_st.sv:259),
  pragma 豁免 output 宣告 (lsu_st.sv:42)。
- **cpu_core 結構閒置**: dispatch stub 僅驅動低 DECODE_WIDTH=6 lane → q_rdy/dv_*/
  rob_disp_v/rob_disp_rdy/rob_disp_idx 高 lane 恆 0; RETIRE_WIDTH=16 但 retire 窄化 →
  rt_req_fl/rt_old_fl/rt_valid_w/rt_tid_w/trap_v_a/ag_rda/ag_prd/ag_fp 高 lane 閒置;
  PRF_WP=12 vs FU 源不足 → prf_wv 高 lane 閒置; L2 fill model 恆回固定 8 指令 →
  dec_block 多數 bit 恆定; 位址空間 < 4GB → fetch_pc/dec_pc/l2_req_addr 高位恆 0;
  fetchbuf_cnt/q_occ 高位不可達 (深度)。以上皆以 mid-line pragma 豁免 (行號未動)。
- **Verilator 5.006 工具行為 (mini 實驗證實)**:
  (a) packed reg 階層 poke 計數; unpacked array 元素 poke 不計自身 coverpoint,
      但值會傳播經 assign 觸發下游 net 重估而計數;
  (b) assign 驅動的 net 直接 poke 不計 (driver 不重估); submodule output 驅動的 net 可計;
  (c) --timing TB 於 initial 直驅 DUT input port 不計 toggle, 必須用 always_ff 鏡像;
  (d) unpacked array (VlUnpacked) force 會觸發 5.006  codegen bug (operator~ 缺失);
  (e) 對 comb 迴路中的 net (q_rdy/rob_disp_rdy/dv_* 等) force 會導致
      "Active region did not converge" — 此類改以 pragma 豁免;
  (f) 計數器類 always_ff 條件寫入: poke '1 後觸發一次遞增事件, 賦值點觀測全 bit 1→0。
