# ORCA v6.3.3 SPEC (單一事實來源)

基線: v6.3.2 (git commit "v6.3.2 baseline")
工具鏈: Verilator 5.006, iverilog 12.0
機器限制: 3GB RAM — 所有 verilator 建置用 `-j 2`; 全樹 lint 會 OOM, 各 agent 只 lint/建置自己範圍
通用 lint 旗標: `-Wno-fatal -Wno-BLKLOOPINIT -Irtl/common` (BLKLOOPINIT 為 v6.3.2 已接受的 Verilator 限制)

## 共享倉庫與分支
- 共享倉庫: /mnt/agents/output/orca_v63_package (coordination hub, 不可直接在此工作)
- 各 agent 用自己的 worktree: `cd /mnt/agents/output/orca_v63_package && git worktree add $HOME/work-<branch> <branch>`
- 禁止 `git worktree prune`; 完成後 commit 到自己 branch 並回報

## 契約 (不可單方面變更)
1. 既有 module 的對外 port 名稱/寬度不得改名; 只能「新增 port(有預設綁定)」或「在父層完成連接」
2. `orca_pkg` 的 type (flit_t/uop_t/paddr_t/tid_t) 不可改定義; 需要新欄位只能加新 type
3. 三個 smoke TB 必須維持 PASS 訊息不變:
   - tb_top: "TB PASS: 7 L2 fetches" (可 >7, 不可為 0)
   - orca_noc_tb: "TB PASS: flit received"
   - ai_tile_smoke_tb: "TB PASS: AIX GEMM completed"
4. 新增 RTL 一律 SystemVerilog, 放對應 rtl/ 子目錄, 檔頭加 ORCA v6.3.3 註解

## Workstream A — CPU 核心 (branch: v633-cpu, agent A)
範圍: rtl/cpu/** , tb/cpu_tile_tb/**
路線圖項目 1+2:
1. PRF 讀埠供給所有 EXU 操作數
   - 現狀: orca_v63_cpu_core.sv L147 `prf #(.WPORTS(8), .RPORTS(10)) u_prf`; rtag 只接 alu/bru/fpu (L152-154)
   - 要求: exu_mul / exu_vec / exu_crypto / LSU AGU 的 prs1/prs2 都經 prf_rtag 讀出 prf_rdata 餵給對應 EXU
   - RPORTS 不足可調大 prf 參數 (prf.sv 只有 31 行, 可改)
2. LSU×4 接入排程器
   - lsu_ld / lsu_st 共 4 條 lane 掛到 isu_mem; issue→AGU→dcache 路徑打通用路徑上的 valid/ready
3. ROB 精確 flush + freelist retire 回接
   - cmt_rob: trap/mispredict 時輸出精確 flush (pc redirect + rob 清空)
   - rnu_freelist: retire 時釋放 old prd 回 freelist; flush 時依 RAT 快照恢復 freelist 狀態 (若 rnu_rat 無快照, 以最小可行機制實作並註明)
驗收: cpu_core lint 0 error (允許 -Wno-BLKLOOPINIT); tb_top smoke PASS

## Workstream B — NoC (branch: v633-noc, agent B)
範圍: rtl/noc/**, rtl/soc/orca_v63_soc.sv 中 NoC mesh 段落, tb/noc_tb/**
路線圖項目 3:
1. Mesh router 埠位對接
   - 現狀: soc L100-181 兩個 mesh (BUF_DEPTH(8) 與 BUF_DEPTH(2)), 多處 `rx_ready()` 懸空, vn/vs 垂直 wrap 只接一半
   - 要求: 所有 rx_ready/tx_ready 完整互連或明確 tie-off (tie 時加註解); 維持 X-Y routing 功能
2. flit_t adapter 接入
   - rtl/noc/orca_flit_adapter.sv 已存在; 將其接在 tile local port ↔ router local port 之間完成 flit_t ↔ 512b DATA_WIDTH 轉換
3. SoC 層 lint 收斂: soc lint 因 3GB RAM 會 OOM, 改用 `--hierarchical` 或只 lint soc+noc 子集證明端口對接正確
驗收: noc 子集 lint 0 error; orca_noc_tb smoke PASS; soc+noc 子集 lint 0 error (不含 cpu/ai 全樹)

## Workstream C — AI Tile (branch: v633-ai, agent C)
範圍: rtl/ai/**, tb/ai_tile_tb/**
路線圖項目 4:
1. npu_attn_engine 接入 ai_tile
   - 現狀: orca_v63_ai_tile.sv L100 註解 "v6.3.4: npu_attn_engine 接入" — 提前到 v6.3.3
   - 要求: 實例化 npu_attn_engine, 掛到 GSCU 分派 (attn 類 AIX uop) 與 cluster/L2 SRAM 資料路徑
2. npu_hbm3_ctrl 完整接入
   - 現狀: L88 已實例化但 phy/hbm pin 未接 (smoke TB 的 hbm_ck_t/hbm_ck_c/hbm_cs_n 懸空)
   - 要求: 接通 npu_hbm3_phy, hbm pin 拉到 ai_tile 端口
驗收: ai 子集 lint 0 error; ai_tile_smoke_tb PASS; 新增一個 attn smoke 檢查 (TB 內 $display 證明 attn engine 被分派執行)

## Stage Gate
每個 agent 回報: 修改/新增檔案清單 + lint 截圖文字 + TB PASS 文字。Orchestrator 驗證後 merge, 全綠才進 Stage 2 (UVM directed sequences + 回歸)。
