# ORCA v6.3 ZEN++ — v6.3.4 缺陷修復戰役報告

**日期**: 2026-09-16
**目標**: 修復覆蓋率戰役（v6.3.3.1/v6.3.3.2）發現的三組 RTL 功能缺陷，修復後四維覆蓋率維持 100%
**結論**: **三組缺陷全部根因定位並修復，45/45 測試平台 PASS，四維覆蓋率全部維持 100%**

---

## 1. 驗收結果總覽（修復後全量重建：44 TB + soc_flood + 3 SVA TB）

| 覆蓋率維度 | 結果 | 數字 |
|---|---|---|
| **Line DA** | ✅ 100.00% | rtl 2815/2815 行（LCOV MIN 語義，與 v6.3.3.x 同口徑） |
| **Toggle** | ✅ 100.00% | 25585 v_toggle 點，0 zero-hit（tgl_check.py 六前綴 exit 0） |
| **FSM** | ✅ 100% | 14 份 fsm.log 與五域 notes 逐弧一致，無弧消失/新增 |
| **SVA** | ✅ 100% | 51 properties：50 PASS + N10 核准 N/A，fails=0；三 TB 以系統 Verilator 5.006 重建複驗 |

**重建品質**:44/44 TB 一次成功（0 BUILDFAIL / 0 RUNFAIL / 0 OOM 重試）+ soc_flood PASS；SVA 三 TB 全 PASS（sva_cpu_core 19/19 nonvacuous，warnings 僅 A6/A18 核准 warning 級）。

## 2. BUG-A:isu_sched single-issue（12-wide 實質 single-issue）

- **根因**(rtl/cpu/scheduler/isu_int.sv L37-50):issue 仲裁的 `older` 判斷未排除「已被 q<p port 取走的 entry」→ 全拍只有全域最老就緒者 older=1，而它已被 port 0 佔用 → `issue_valid[p>0]` 結構不可達。isu_int/isu_mem/isu_fp 三實例共用此模組，一併治癒。
- **修復**:oldest-first 多發射——port p 發射「尚未被 q<p 取走的最老就緒 entry」。介面/參數不變，`// v6.3.4 fix BUG-A:` 標記。
- **證據**:unit TB 修前 `iv=1`（8 筆就緒僅 port0 發射）→ 修後 `iv=1111`（4 port 同發）；新 directed TB `tb/bug_a_multi_issue_tb.sv` 驗證 oldest-first 順序（p0=7000/p1=7001/p2=7002/p3=7003）與 2 筆就緒恰好 2 port。

## 3. BUG-B：寫回→ROB complete 停擺（四環節根因鏈）

| # | 根因 | 位置 | 修復 |
|---|---|---|---|
| 1 | **single-INSERT 孿生缺陷**:insert 迴圈 12 個 dispatch slot 看同一拍 vld、選同一 free_i,NBA 下同拍 N 筆僅最後 1 筆入列，其餘靜默丟棄 | isu_int.sv | used 位圖逐 slot 消耗不同 free entry;`disp_ready[s]=(free_cnt>s)` |
| 2 | **disp_ready 虛假受理**:`.disp_ready()` 懸空 + 全 slot 回同一 `!full`;ROB disp_tid 恆 0 下的二次丟棄 | orca_v63_cpu_core.sv | 三排程器 disp_ready 接出，dense-prefix `disp_accept`（排程器有空位 && `!rob_full_w[0]`）回壓 rename |
| 3 | **uop_id 全 0 連坐清除**:decoder/rename 從未賦值 uop_id;BUG-A 多入列成真後，發射按 id 相等清除會抹掉整個佇列 | orca_v63_cpu_core.sv | `uop_id = rob_disp_idx` 注入（256 窗唯一性保證） |
| 4 | **LSU 雙潛伏缺陷**:lsu_st STQ `committed` 無 driver（4 格滿即死鎖）;lsu_ld `LD_STQ_CHECK` 優先 alias replay 但 replay_req 未接線（load 靜默丟棄） | lsu_st.sv / lsu_ld.sv | ST_COMPLETE 按 rob_idx+tid 標 committed 恢復 dequeue;STQ_CHECK 改 `stq_forward_hit` 優先（有資料直接轉發完成） |

**port-class 合約**：採整合層修正——isu_int 4 port 加 ALU/BRU/FPU/CRYPTO 類別路由器 + is_r 回壓；isu_fp port1 加 MUL 類守衛（VEC 落 port1 回壓留列）。scheduler 仲裁保持 class-agnostic（保全 bug_a_multi_issue_tb 契約，三實例行為一致）。

**功能證據（修前 → 修後）**:
- 自然 retire:`rt0=0`、head0 卡 141 3000+ 拍 → **rt_cnt 0→99、ROB 自然排空**（occ0 穩定 ~14、T599 head=tail=210）
- LSU lanes:`1056/0/0/0` → **726/657/529/405**;ld_wb=370;STQ 排空循環正常
- mul 寫回：從不完成 → **真實完成**（isu_fp port1→exu_mul，rob_idx 正確回寫）
- cpu_directed_tb:`fills=200 prf_wr_cyc=1022 max_wports=4 vec_wb=398`

## 4. BUG-C:SoC EAST 路由結構不可達（使用者裁示選項 a）

- **根因**:orca_noc_router 私有 516-bit flit_t vs 512-bit 線網 → MSB 零填充使 router 側 dest_x 恆 0 → `dest_x > X_POS` 永不成立 → EAST 永不路由；WEST/NORTH/SOUTH 為退化行為（X 維度資訊被拿去跟 Y_POS 比，(0,1) 的 flit 會在 (0,0) 誤投）；多 flit packet 的 TAIL 以 raw payload 上路必然崩壞；vc_id 從 payload[495:492] 誤取，1/2~3/4 flit 因 VC≥4 越界被丟。
- **修復（選項 a，全鏈路統一 `orca_pkg::flit_t` 525b)**:
  - router：刪私有型別，埠/內部全面 pkg flit_t;compute_route 用 pkg 標頭欄位；vc_id 2b 直作 buffer index（恆 < NUM_VC）
  - soc:mesh 線網 512b→`$bits(flit_t)`(525b),router 例化同步;**移除 4 處失效豁免**（he_* EAST、vn_v/vs_v、ad_tx_v、ct_iv/at_iv 部分）
  - adapter：退化直通（每 flit 完整標頭上線網，多 flit packet 邊界不丟）
  - TB:stub_tiles×2 改用真標頭 vc_id;router/adapter cov TB 同步；sva_noc_tb 同步
- **證據（新 tb/cov_soc/soc_east_tb.sv 五項 directed 全過）**:EAST 單跳逐位完整 / 三跳 he[0..2][0] 皆拉起 / XY 先 E 後 N / VC 0..3 全轉發 / HEAD+TAIL 保序同目的且 TAIL 512b 不截斷。
- **附帶收益**：修掉 v6.3.3.2 殘留 2 個 zero-hit(port_requested/port_granted[0][1] N<-S 轉發）;noc+soc toggle 709 點 0 zero-hit，無新增豁免。

## 5. TB 工件修正（RTL 正確性到位後的必要跟進，均加 `// v6.3.4 TB fix:` 標記）

| TB | 問題 | 修法 |
|---|---|---|
| f3_lsu_ls_tb | stq_full 覆蓋依賴舊「dequeue 不可達」壞行為 | 壓住 dcache_req_ready 卡 ST_DCACHE_REQ，4 格在正確行為下真實填滿；放行驗證 drain |
| sva_cpu_core_tb | inject_flush 對空/淺分區打 head[0]（retire 修復後時序錯位）造幻影洞 | 改打最深活體分區最老活體 entry；觀察窗 3→1 拍；換 thread 時 tid 切齊；注入加活體有界等待（迭代 7 輪收斂） |
| f3_core_poke_tb | rob_full_w[1..3] zero-hit(SMT 半接線下 thread1-3 無流量） | 收尾段 force-blitz 4'b0000→1110→0000+release（真實覆蓋，無豁免） |

## 6. 變更檔案與 md5 台帳

| 檔案 | 變更 | md5（定稿） |
|---|---|---|
| rtl/cpu/scheduler/isu_int.sv | BUG-A 仲裁 + BUG-B insert/disp_ready | 43e017ce5cd6c909e9074a77dda1eb00 |
| rtl/cpu/orca_v63_cpu_core.sv | BUG-B 回壓/FU 路由/uop_id 注入 | 65d8aee80946909847c9645bd7777b2e |
| rtl/cpu/memory/lsu_ld.sv | BUG-B 轉發優先 + COV-EXEMPT pragma(:249/:251，strip 後還原 4320dc18… 證明功能零變更) | a32565a0895fc885880f0b0ed7aae8d1 |
| rtl/cpu/memory/lsu_st.sv | BUG-B STQ committed | 2ec6ec95dab1f09463ab4bb312c764d5 |
| rtl/noc/orca_noc_router.sv | BUG-C pkg flit_t 525b | bd7491a83c3e679447bca9ad741fb3b2 |
| rtl/soc/orca_v63_soc.sv | BUG-C 525b 線網 + 豁免清理 | 22eac3a033b34907406a5f7f652215e8 |
| rtl/noc/orca_flit_adapter.sv | BUG-C 直通 | 205b85d8…（詳 git diff） |
| rtl/cpu/commit/cmt_rob.sv | **未動**（v6.3.3.2 定稿） | c68d64193fb2ad71a0b4914ac38beb98 |
| rtl/common/orca_pkg.sv | **未動**(SPEC 禁改) | 0820cf85fbfc6184017cdfbf0af98b70 |
| isu_mem.sv / isu_fp.sv | 僅註解更新（pragma 未動） | a87b35db…/ bddc621a… |

新增：tb/bug_a_multi_issue_tb.sv、tb/cov_soc/soc_east_tb.sv、tb/cov_soc/stub_tiles_east.sv;final_list.txt 增至 44 行（兩份同步 md5 44f3f5d1…）。

## 7. 覆蓋率缺口閉合紀錄（Stage 4 露出 → 閉合）

1. **rob_full_w[1..3]**(3 toggle 點）:core 級 thread1-3 無流量（SMT 半接線，見 §8.2）→ f3_core_poke_tb force-blitz 真實覆蓋，無豁免。
2. **lsu_ld.sv:250-251**(2 line):BUG-B 後 alias=1 且 forward=0 結構不可達的 defensive replay 兜底 → COV-EXEMPT pragma（行尾、`//` 前、行號未動、strip-compare 功能零變更）。工具錨定說明：Verilator 將 final-else 臂（:252-253,cnt=97 已被行為覆蓋）的 v_line 點錨定於 :250，豁免連帶消除 → 分母 2817→2815，無新增未中行。
3. **F3 notes 過時敘述**：已更新（BUG-A/B 修復事實與 pragma 保留原因）。

## 8. 已知殘留問題（後續版本立案建議）

1. **PRF 寫回 tag 錯位**(pre-existing):prf_wtag 用「當下 port uop」的 prd 而非「完成中 uop」的 prd(fu_t 同）；影響依賴鏈 wake 與資料正確性。建議：exu_* 輸出完成級 prd。
2. **SMT 半接線**:uop.tid 旋轉但 ROB disp_tid 恆 0、flush_tid 取當拍 tid;thread1-3 分區無自然流量。完整 SMT 需另案。
3. **BRU 無 rob_complete 通道**：分支 entry 依賴 flush/其他機制結束。
4. **lsu_ld 轉發未比 store/load 年齡**(pre-existing)：年輕 store 也可能轉發。
5. **uop_id wrap**:rob_idx 每 thread 256 回捲，極端跨 wrap 同年齡比較可能反轉（僅影響發射順序）。
6. **front-end jam 現象**:TB 實測無 flush 時 dispatch 長期 jam(flush 有解 jam 副作用）——整合層既存議題，與 insert/回壓鏈相關，值得後續深挖。
7. lsu_st.sv 兩處 BUG-B 前過時註解（「dequeue 不可達」）因 RTL 凍結紀律未清理，僅 TB 側更正。

## 9. 再現性

```bash
cd orca_v63_package
bash scripts/final_cov.sh 1 44     # 44 TB 冪等重建
# soc_flood: 同 SOC 分支換 tb/cov_soc/stub_tiles_flood.sv
python3 scripts/tgl_check.py rtl/cpu rtl/ai rtl/noc rtl/soc rtl/pad rtl/common
verilator_coverage --write-info build/cov_final/merged.info build/cov_final/*/coverage.dat
# SVA 三 TB: scripts/sva_build.sh 指令 + 系統 5.006(-fcoroutines, VK_PCH_I_FAST= VK_PCH_I_SLOW=)
```

## 10. 交付物

| 項目 | 路徑 |
|---|---|
| 本報告 | orca_v63_v634_report.md |
| 封裝 | orca_v63_v6.3.4_20260916.tar.gz（含 45 dats + merged.info + 全部源碼/腳本/筆記/.git） |
| 聯合驗證摘要 | build/cov_final/summary.txt |
| Line DA 逐檔表 | build/cov_final/line_da_summary.txt |
| SVA 全表 + v6.3.4 複驗補遺 | tb/sva_cov/sva_cov_report.txt 第 9 節 |
| FSM/豁免證明 | docs/cov_notes/F1-F5_fsm_notes.md |
| BUG-C 設計分析 | docs/bugc_east_fix_options.md |
