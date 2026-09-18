# PROVENANCE — ORCA AI 加速器系列（併入說明）

## 來源

- 來源封包：使用者上傳 `ORCA_AI_Accelerators_v2.1_Final_20260907.tar.gz`（2026-09-07）。
- 上游 repo：`github.com/tonythetiger168/orca-ai-accelerators`。
- 內容：六代 AI 加速器（v5.0 Kestrel／v5.1 Falcon／v5.2 Hawk／v6.0 Phoenix／v6.1 Phoenix-E／v6.2 Phoenix+）的 RTL、SoC 整合檔、UCIe D2D testbench 與各代架構文件。

## 授權注意

**本 accelerator 系列為 Apache-2.0 授權**（見 `accelerators/LICENSE`），與主專案（ORCA v6.3 SoC）的 **MIT** 授權不同。使用、修改或再散布本目錄內容時，需遵守 Apache-2.0 條款（保留授權聲明與 NOTICE、專利授權條款等）。

## 恢復處理說明

原封包中的 16 個 SystemVerilog 檔案在打包時被剝除所有換行符（`\n`）與雙引號（`"`）：每檔變成單行、字串變成單引號包裹、`include 檔名失去引號；各行的前導縮排空白保留，成為恢復錨點。上游 git 歷史同樣損壞，無法取巧。

恢復方式：以啟發式腳本 `restore_newlines.py`（留存於 `ai_accel_work/`，可重複執行，一律從 `*.sv.orig` 備份重新生成）依下列規則恢復：

1. **雙引號恢復**：區分 SV 合法單引號語法（`'0`/`'1`/`'x`/`'z`、尺寸 literal `4'b1010`/`8'sd127`、cast `DATA_WIDTH'(6)`、`'{...}` pattern），其餘成對單引號字串還原為雙引號（僅 testbench 有 `$display`/`$fatal`/`$dumpfile` 字串）。
2. **換行恢復**：backtick 指令前斷行並補回 `include "..."` 引號；`()` 深度為 0 的 `;` 後斷行（for 迴圈內不斷）；`endmodule`/`endcase` 等區塊結束關鍵字前斷行；「2+ 連續空白（保留的縮排錨點）+ code token」斷行；`//` 註解終止偵測（註解後接 2+ 空白 + 程式碼 token／賦值語句／case 標籤即斷行）。
3. 每修一版即對 16 檔逐個跑 Verilator lint 收斂。

### Markdown 文件恢復（第二批）

同批打包缺陷亦影響 15 個 Markdown 文件（`README.md`、`CONTRIBUTING.md`、`docs/` 下 7 檔、六代 `docs/*_Architecture.md`）：同樣被剝除所有 `\n` 與 `"` 變成單行，前導縮排空白保留。以啟發式腳本 `restore_markdown.py`（留存於 `ai_accel_work/`，可重複執行，一律從 `.orig` 備份重新生成）恢復，規則包括：``` 圍欄獨立成行、header/`---`/表格列/列表項目斷行、HTML 結束標籤後斷行、**僅 HTML 屬性**上下文（`attr='value'` 配對）把單引號還原為雙引號（散文 apostrophe 如 `Alibaba's` 保持不動）、保留縮排錨點的程式碼斷行。

- 驗證：每檔 ``` 圍欄配對為偶數、表格區塊 pipe 數一致、全檔 `pandoc -f gfm -t html` 渲染無錯誤（15/15 通過），並逐檔目視抽查 header/列表/表格結構。
- **ASCII art 為 best-effort**：單欄箱線圖（如 Roadmap、Phoenix 系列方塊圖）幾乎完全復原；v5.1 Falcon／v5.2 Hawk 區塊圖中「兩個子方盒並排」的列因行列間隙相同而無法唯一判定斷點，部分列保持黏接或過度切分（內容完整、僅排版受損）；CoWoS 熱堆疊圖、Kestrel 區塊圖為近似復原。少數無標點的中文段落黏接（如 THead 對比文末）依「寧少斷勿斷錯」原則保留原樣。

### 恢復過程中一併修正的「原始碼本身」缺陷（非剝除造成，不修則無法通過編譯）

| 檔案 | 原始缺陷 | 處置 |
|---|---|---|
| `v6_0_phoenix/rtl/orca_tpe_v6.sv` | `ti`/`tj` 宣告為 `genvar` 卻用於 `always_ff` 程序性 for 迴圈（違反 IEEE 1800-2017 §27.4） | 程序性迴圈改為 `for (int ti/tj = ...)`（generate 迴圈 `begin : act_i/act_j` 維持 genvar 用法） |
| `v6_1_phoenix_e/rtl/orca_tpe_v6_1.sv`、`v6_2_phoenix_plus/rtl/orca_tpe_v6_2.sv` | 同上（這兩檔的 `ti`/`tj` 僅用於程序性迴圈） | 宣告改為 `integer ti, tj;` |
| `v5_0_kestrel/integration/orca_soc_top_v5_npu.sv` | 例化時連接了 `orca_npu_v5` 不存在的 4 個 `npu_mem_*` 接腳（原始碼註解自承 “Unused direct memory interface”） | 移除該 4 個空／常數連接（行為中立，原本就無法編譯） |
| `tb/ucie/tb_ucie_d2d.sv` | 將 TPE 的**輸出**埠 `mem_arvalid`/`mem_awvalid`/`mem_wdata`/`mem_wstrb`/`mem_wvalid` 接到常數（電氣短路，Verilator PORTSHORT 硬錯誤） | 該 5 個輸出埠改為留空 `()`（兩個 die 共 10 處） |

## Verilator lint 驗證結果

- 工具：**Verilator 5.006**（Debian 5.006-3）。
- 指令：`verilator --lint-only -Wno-fatal -Wno-BLKLOOPINIT -Iaccelerators/include <檔案> --top-module <top>`；testbench 另加 `--timing`；integration 檔連同對應 rtl 檔一起編譯。
- `-Wno-BLKLOOPINIT` 說明：Verilator 5.006 不支援「procedural for 迴圈內對 unpacked array 做 nonblocking assignment」（原始程式碼風格，見 npu_v5_1/npu_v5_2/tpe_v6_1/tpe_v6_2），屬工具限制而非設計錯誤，故豁免。
- **結果：16/16 檔 0 error。**

| 檔案 | 恢復後行數 | lint | warning 數（類型） |
|---|---|---|---|
| v5_0_kestrel/rtl/orca_npu_v5.sv | 285 | PASS | 36（WIDTH；26 來自 orca_params.sv，10 本檔） |
| v5_1_falcon/rtl/orca_npu_v5_1.sv | 195 | PASS | 29（WIDTH；26 params + 3 本檔） |
| v5_2_hawk/rtl/orca_npu_v5_2.sv | 285 | PASS | 35（WIDTH；26 params + 9 本檔） |
| v6_0_phoenix/rtl/orca_tpe_v6.sv | 217 | PASS | 34（WIDTH；26 params + 8 本檔） |
| v6_0_phoenix/rtl/orca_ame_v6.sv | 134 | PASS | 34（WIDTH×33、CASEINCOMPLETE×1） |
| v6_1_phoenix_e/rtl/orca_tpe_v6_1.sv | 210 | PASS | 33（WIDTH；26 params + 7 本檔） |
| v6_1_phoenix_e/rtl/orca_ame_v6_1.sv | 121 | PASS | 34（WIDTH×33、CASEINCOMPLETE×1） |
| v6_2_phoenix_plus/rtl/orca_tpe_v6_2.sv | 245 | PASS | 35（WIDTH×34、CASEOVERLAP×1） |
| v6_2_phoenix_plus/rtl/orca_ame_v6_2.sv | 165 | PASS | 35（WIDTH×34、CASEINCOMPLETE×1） |
| v5_0_kestrel/integration/orca_soc_top_v5_npu.sv | 107 | PASS | 36（WIDTH；全部來自 include 的子模組/params） |
| v5_1_falcon/integration/orca_soc_top_v5_1_npu.sv | 87 | PASS | 29（WIDTH；同上） |
| v5_2_hawk/integration/orca_soc_top_v5_2_npu.sv | 101 | PASS | 35（WIDTH；同上） |
| v6_0_phoenix/integration/orca_soc_top_v6_npu.sv | 102 | PASS | 42（WIDTH×41、CASEINCOMPLETE×1；來自子模組/params） |
| v6_1_phoenix_e/integration/orca_soc_top_v6_1_npu.sv | 102 | PASS | 41（WIDTH×40、CASEINCOMPLETE×1；同上） |
| v6_2_phoenix_plus/integration/orca_soc_top_v6_2_npu.sv | 218 | PASS | 44（WIDTH×42、CASEINCOMPLETE×1、CASEOVERLAP×1；同上） |
| tb/ucie/tb_ucie_d2d.sv | 183 | PASS | 35（WIDTH×34、CASEOVERLAP×1；來自 tpe_v6_2/params） |

註：每檔都有 26 個 WIDTH warning 來自**完好未修改**的 `include/orca_params.sv`（`localparam int X = 2'b00` 類寬度不匹配），屬原始碼既有風格；CASEINCOMPLETE/CASEOVERLAP 亦為原始碼既有的 case 寫法。所有 warning 皆非恢復錯誤造成（無 UNDRIVEN/UNUSED 類警告）。

## 性質說明

本目錄為 **library 性質**：加速器系列**未整合進 v6.3 SoC** 的 rtl/、tb/、scripts/ 或覆蓋率流程，不影響主專案任何既有內容與覆蓋率數據。`include/orca_params.sv`、`include/orca_pkg.sv` 複製自 cpu/v5_0/rtl（完好檔案），使本目錄可獨立 lint／編譯，不需依賴主專案檔案。
