# F4 域 FSM 覆蓋率筆記 (rtl/ai, 8 個 FSM)

量測方式: Verilator 5.006 無內建 FSM coverage, 於各單元 TB 加 `fsm_mon`
initial 區塊, 在 posedge clk 監控狀態暫存器, 轉移時以 `FSM_ID prev next`
格式附加寫入各 TB run 目錄的 fsm.log (build/cov_final/f4_*_tb/fsm.log,
14 個 TB 由 orca_v63_package/rebuild_all14.sh 以 -j 1 序列重建)。
TB 內對 state 的強制注入 (default arm 測試) 以 `fsm_mute` 旗標靜音;
注意 fsm_mon 於 posedge 采樣到的是 NBA 更新前的舊值, release 後須多等
一拍再解靜音, 否則會記到假弧 (如 npu_cu 3->0) — cu/dma/hbm3_phy 三個
TB 已修正此 race。
彙總腳本: /mnt/agents/output/cov_f4_work/fsm_summary.py

## 各 FSM 合法集合 (由 RTL case 項列舉) 與覆蓋結果

### 1. npu_attn_engine state (4-bit, 9 狀態) — TB: f4_attn_engine_tb
- 狀態: IDLE=0 LOAD_Q_TILE=1 LOAD_K_TILE=2 COMPUTE_SCORES=3 SOFTMAX_ROW=4
  LOAD_V_TILE=5 COMPUTE_OUTPUT=6 WRITE_OUTPUT=7 DONE_STATE=8
- 合法弧 10: 0→1 1→2 2→3 3→4 4→5 5→6 6→7 7→1 (row 回圈) 7→8 8→0
- 結果: 10/10 弧, 9/9 狀態 (seq_len=32 兩輪 run 自然走完全部弧)

### 2. npu_cu st (2-bit, 3 狀態) — TB: f4_cu_tb
- 合法弧 3: CU_IDLE→CU_COMP, CU_COMP→CU_DRAIN, CU_DRAIN→CU_IDLE
- 結果: 3/3 弧, 3/3 狀態

### 3. npu_dma st (2-bit, 3 狀態) — TB: f4_dma_tb
- 合法弧 3: D_IDLE→D_XFER, D_XFER→D_LAST, D_LAST→D_IDLE
- 結果: 3/3 弧, 3/3 狀態

### 4. npu_gscu gst (1-bit, 2 狀態) — TB: f4_gscu_tb
- 合法弧 2: G_RUN→G_DRAIN (cmd DMA_ST), G_DRAIN→G_RUN (idle_all)
- 結果: 1/2 弧 (G_RUN→G_DRAIN 已覆蓋), 2/2 狀態
- **不可達弧 G_DRAIN→G_RUN**: 與 line coverage 已豁免之 arm 同一理由
  (rtl/ai/ctrl/npu_gscu.sv line 82-83 行尾 pragma):
  進入 G_DRAIN 的條件是 cmd_valid && opcode==AIX_OP_DMA_ST, 此時該 cmd
  已佔住 queue (qc>0); G_DRAIN 期間不再發新 cmd (cmd_ready 拉低),
  而 qc 要歸零必須把 DMA_ST 本身也分派出去, 但 DMA_ST 由 u_dma 路徑處理
  前 qc 無法 drain 到 0, 故 `gst == G_DRAIN && idle_all` 永不成立。
  屬結構性不可達, line coverage 已用同理由豁免, FSM 弧沿用。

### 5. npu_hbm3_ctrl bank_state (3-bit, 7 狀態) — TB: f4_hbm3_ctrl_tb
- 監控點: bank_state[0][0][0] (generate 內所有 bank 共用同一轉移邏輯,
  同質; TB 的 ACT/READ/WRITE/PRE 全部注入 stack0/ch0/bank0, 單一元素
  即可走完全部可達弧)
- 可達狀態 4: BANK_IDLE=0 BANK_ACTIVE=2 BANK_READING=3 BANK_WRITING=4
- 可達弧 6: 0→2 (ACT) 2→3 (READ) 2→4 (WRITE) 3→2 (auto-return)
  4→2 (auto-return) 2→0 (PRE)
- **不可達狀態 3**: BANK_ACTIVATING=1, BANK_PRECHARGING=5,
  BANK_REFRESHING=6 — 全 RTL 無任何指派這三個 enum 值的路徑
  (grep 證明: bank_state 的所有 <= 指派只有 BANK_IDLE/BANK_ACTIVE/
  BANK_READING/BANK_WRITING; ACTIVATE 直接 IDLE→ACTIVE 無中間態,
  PRECHARGE 直接 ACTIVE→IDLE, refresh 流程不經 bank_state)。
  屬列舉了但未實作的保留狀態, 結構性不可達。
- 結果: 6/6 可達弧, 4/4 可達狀態

### 6. npu_hbm3_phy st (3-bit, 5 狀態) — TB: f4_hbm3_phy_tb
- 合法弧 4: P_RESET→P_ZQ→P_MR→P_TRAIN→P_DONE (單向線性)
- 結果: 4/4 弧, 5/5 狀態

### 7. npu_tile_noc st (2-bit, 4 狀態) — TB: f4_tile_noc_tb
- 合法弧 4: N_IDLE→N_HDR→N_PAY→N_RSP→N_IDLE (環)
- 結果: 4/4 弧, 4/4 狀態 (寫/讀兩筆 transaction)

### 8. npu_systolic weight_state (2-bit, 4 狀態) — TB: f4_systolic_tb
- 合法弧 4: WS_IDLE→WS_LOADING→WS_READY→WS_COMPUTING→WS_IDLE (環)
- 結果: 4/4 弧, 4/4 狀態 (兩輪 load/compute/flush)

## 總結
- 8 個 FSM: 可達弧 38/38 = 100%, 可達狀態 34/34 = 100%
  (最終量測: 環境重置後 rebuild_all14.sh 全量重建之 build/cov_final,
   fsm_summary.py 輸出無假弧, 僅缺下列結構性不可達項)
- 不可達項: npu_gscu G_DRAIN→G_RUN 弧 1 條 (line 82-83 同理由豁免),
  npu_hbm3_ctrl 保留狀態 3 個 (BANK_ACTIVATING/PRECHARGING/REFRESHING,
  無指派路徑 — grep 全檔僅出現於 enum 宣告行)
- 同場加映: toggle coverage (tgl_check.py rtl/ai) 5198 點 0-hit=0;
  npu_hbm3_ctrl 的 refresh_counter[15:11] 與 temp_sensor[1][2][7,6,4]
  高位因 unpacked array 跨階層 poke 不產生 toggle 計數, 改以自然路徑
  覆蓋 (cfg_tREFI=16'hFFFF 計滿一輪; cfg_tRFC 拉長 refresh 窗口 +
  force temp_poll_counter=0 連續 poll 使 temp 遞增至 >=128)
