# BUG-C 修復方案建議書：SoC 層 EAST 路由結構不可達（adapter↔router flit 標頭錯位）

- 版本：ORCA v6.3.4 規劃 / 分析基準：v6.3.3.2 程式碼現況
- 性質：唯讀分析；本文件為唯一產出，未修改任何 rtl/tb/scripts 檔案
- 引用格式：`檔案:行號`

---

## 0. 摘要（TL;DR）

根因確認成立，且比原描述更複雜。現狀存在 **四套互不相同** 的 flit 位元布局：

1. `orca_pkg::flit_t` = **525 bit**（非 512！payload 512b + 13b 標頭/valid），見 `rtl/common/orca_pkg.sv:233-242`。
2. router 模組內私有 `flit_t` = **516 bit**（472b payload + 44b 標頭），見 `rtl/noc/orca_noc_router.sv:100-110`。
3. adapter 的 512b 線網編碼（head flit：16b 標頭 + payload[495:0]，**不帶 vc_id/ftype**），見 `rtl/noc/orca_flit_adapter.sv:23-27`。
4. stub TB 假設的 512b 布局（vc 於 wire[491:488]），見 `tb/cov_soc/stub_tiles.sv:29-35`。

逐位元推導結果：**router 實際讀到的 vc_id 在 wire[495:492]（= pkg payload[495:492]），而非任務書/報告所述的 [491:488]**（詳 §2.4，與現況描述不符處如實記錄）。EAST 不可達機制與原描述一致（dest_x 恆 0）。

**推薦：選項 (a)** — router 刪除私有型別、埠全面改用 `orca_pkg::flit_t`，SoC 線網由 512b 加寬至 `$bits(flit_t)`=525b，adapter 退化為直通。理由：單一型別真相源、每個 flit 自帶完整標頭（body/tail 可路由，順便修好目前多 flit packet 的隱性崩壞）、512b payload 完整保留（HBM3/CHI 相容）。選項 (c)（512b header 重映射）為線網寬度受限時的備案。

---

## 1. 現狀欄位映射（逐位元實證）

### 1.1 orca_pkg::flit_t（525 bit）— `rtl/common/orca_pkg.sv:233-242`

NOC 參數：`NOC_DATA_WIDTH=512, NOC_VC=4, NOC_X_BITS=2, NOC_Y_BITS=2`（`orca_pkg.sv:89-94`）。
packed struct 第一個成員佔 MSB：

| 欄位 | 位元區間 | 寬度 |
|---|---|---|
| payload | [524:13] | 512 |
| dest_x | [12:11] | 2 |
| dest_y | [10:9] | 2 |
| src_x | [8:7] | 2 |
| src_y | [6:5] | 2 |
| vc_id | [4:3] | 2 |
| ftype | [2:1] | 2 |
| valid | [0] | 1 |

**注意：pkg flit_t 總寬 525b，不是 512b。** 512 僅為 payload。SPEC-v633.md:15 明定「`orca_pkg` 的 type (flit_t/…) 不可改定義」，故不能為了遷就 512b 線網而修改此 struct。

### 1.2 router 私有 flit_t（516 bit）— `rtl/noc/orca_noc_router.sv:100-110`

| 欄位 | struct 位元 | 對映 512b 線網（struct[511:0]=wire，[515:512] 零填充）|
|---|---|---|
| dest_x | [515:512] | **恆 4'b0000（落於線網之外）** |
| dest_y | [511:508] | wire[511:508] |
| src_x | [507:504] | wire[507:504] |
| src_y | [503:500] | wire[503:500] |
| msg_type | [499:496] | wire[499:496] |
| vc_id | [495:492] | **wire[495:492]** |
| packet_id | [491:480] | wire[491:480] |
| flit_type | [479:472] | wire[479:472] |
| payload | [471:0] | wire[471:0] |

機制：`rx_flit[p] = north_rx_data;`（`orca_noc_router.sv:153-157`）將 512b 零擴展至 516b，MSB 4 位（dest_x）恆 0 → `compute_route` 的 `dest_x > X_POS`（`:134`）永不成立 → **EAST 結構性不可達**。tx 方向 `north_tx_data = tx_flit[...]`（`:274-283`）為 516b→512b 截斷，dest_x 欄位同樣被丟棄。模組檔頭註解（`:87-92`）自稱 `[511:500]` 放 16b dest/src，算術本身就對不上（12≠16），註解不可作為依據。

### 1.3 adapter 的 512b 線網編碼 — `rtl/noc/orca_flit_adapter.sv:23-27`

head/single flit：
`r_rx_data = {2'b0, dest_x, 2'b0, dest_y, 2'b0, src_x, 2'b0, src_y, payload[495:0]}`

| wire 位元 | 內容 |
|---|---|
| [511:510] | 2'b0 |
| [509:508] | 真 dest_x |
| [507:506] | 2'b0 |
| [505:504] | 真 dest_y |
| [503:502] | 2'b0 |
| [501:500] | 真 src_x |
| [499:498] | 2'b0 |
| [497:496] | 真 src_y |
| [495:0] | pkg payload[495:0]（**payload 高 16 位被截斷**）|

body/tail flit：整條 wire = raw payload 512b，**線上無任何標頭**。

### 1.4 adapter↔router 疊合後的實際錯位（head flit）

| router 解讀 | 實際內容 | 偏移量 |
|---|---|---|
| dest_x = 0 | （零填充） | 真 dest_x 下移 4 位 |
| dest_y = {2'b0, **真 dest_x**} | 數值等於真 dest_x | +4 |
| src_x = {2'b0, 真 dest_y} | | +4 |
| src_y = {2'b0, 真 src_x} | | +4 |
| msg_type = {2'b0, 真 src_y} | | +4 |
| vc_id = wire[495:492] = **pkg payload[495:492]** | 純 payload 資料 | — |
| packet_id = wire[491:480] = payload[491:480] | | — |
| flit_type = wire[479:472] = payload[479:472] | | — |
| payload = wire[471:0] = payload[471:0] | 對齊 | 0 |

**路由實效**：`compute_route(flit.dest_x=0, flit.dest_y=真dest_x)` — X 維度路由決策實際上是拿「真 dest_x」去跟 **Y_POS** 比較，Y 維度資訊完全不參與路由。

### 1.5 與任務書/報告描述不符之處（如實記錄）

1. **vc_id 落點**：任務書與 v6.3.3.2 報告（`orca_v63_v6332_report.md:95`）稱「vc_id 實位於 wire[491:488]」。逐位元推導（§1.2–1.4）顯示 router 實際讀取 **wire[495:492] = pkg payload[495:492]**。[491:488] 是 stub 作者假設的「512b 版 router struct」（dest[511:496]、msg_type[495:492]、vc[491:488]、packet_id[487:476]、flit_type[475:468]、payload[467:0]）之落點，見 `stub_tiles.sv:29-35`。實際後果：stub 把 `cnt[1:0]` 寫在 pl[491:488]（落入 router 的 packet_id），而 router 真正用作 VC index 的 pl[495:492] 被 stub 填入 `cnt[3:0]`（0~15）。以 NUM_VC=4 計，注入 flit 的「實效 VC」有 1/2～3/4 ≥4（如 TILE_ID=3 時 cnt 步進 4，僅 1/4 落於 0..3），越界 VC 的 buffer 寫入在 Verilator 下被丟棄。stub 註解「必須填入 0~3 否則越界丟棄」方向正確但位址差了 4 bit。
2. **pkg flit_t 位寬**：描述隱含「pkg flit_t ≈ 512b 線網格式」，實際為 525b。這直接影響選項 (a) 的設計（§3.1）。
3. EAST 不可達機制（MSB 零填充 → dest_x 恆 0 → `dest_x > X_POS` 永不成立）與描述**完全一致**。

---

## 2. 現狀行為逐方向分析（WEST/NORTH/SOUTH 是否「碰巧正確」？）

Router 位於 (X_POS, Y_POS)，SoC 層每個 flit 解出 dest_x≡0、dest_y≡真dest_x：

| 方向 | 條件（router 視角） | 現狀行為 | 判定 |
|---|---|---|---|
| EAST | dest_x > X_POS | 0 > X_POS 永不成立 → **永不路由**，`he_v/he_r` 恆 0/1（`orca_v63_soc.sv:73` 豁免註解） | 結構不可達（BUG-C 本體） |
| WEST | dest_x < X_POS | 對所有 X_POS≥1 的 router、所有非 LOCAL flit **無條件成立** → 全部向西漂移到第 0 列 | **碰巧「看似」正確**：它只是把一切推向 x=0，與真目的地無關 |
| LOCAL | dest_x==X_POS && dest_y==Y_POS | 僅 x=0 列可能；(0,0) 要求真dest_x=0，(0,1) 要求真dest_x=1 → 真正目的地 (0,1) 的 flit 會在 (0,0) 被誤投給 CPU tile 0 | y 維度投遞錯誤，僅 x=0 列可投遞（`orca_v63_soc.sv:41,76` 豁免註解） |
| NORTH | dest_y > Y_POS | 僅 x=0 列；R(0,0) 對真dest_x≥1 全部北送；R(0,1) 對真dest_x∈{2,3} 再北送 → **撞上 y=1 北緣 tie-off 被默默丟棄**（`orca_v63_soc.sv:127-129`） | 部分 flit 被丟；vn_v/vs_v 僅 x=0 可翻轉（`:72` 豁免註解） |
| SOUTH | dest_y < Y_POS | 僅 (0,1) 且真dest_x=0 時南送 → AI tile 0 → CPU tile 0 路徑可用 | 碰巧可用 |

結論：WEST/NORTH/SOUTH 目前**不是**功能正確，而是「dest_x 恆 0 + 欄位下移 4 位」下的退化行為，恰好讓第 0 列的垂直鏈路與部分 LOCAL 投遞有翻轉。修復後此行為必然改變（見 §4）。

### 2.5 附帶發現：多 flit packet 在 SoC 層目前必然崩壞

`npu_tile_noc.sv:31-36` 會發 HEAD（payload={dma_addr,448'b0}）+ TAIL（payload=dma_wdata 全 512b）兩拍 packet。adapter 對 TAIL 送 raw payload、線上無標頭（`orca_flit_adapter.sv:27`），router 又對**每個** flit 重新解標頭路由（無 wormhole 路由狀態）→ TAIL flit 以 dma 資料的高位當 dest_y 路由，去向隨資料而異。**任何 BUG-C 修復都應一併解決 body/tail 路由**（選項 (a) 天然解決；(b)/(c) 需另行處理，見 §3）。

### 2.6 vc_id 用法一致性盤點

| 模組 | vc_id 用法 | 一致性 |
|---|---|---|
| `orca_pkg.sv:239` | flit_t.vc_id，2b，[4:3] | 定義 |
| `orca_flit_adapter.sv:23-27` | **完全不讀、不上線** | ❌ pkg vc_id 在 SoC 層是死欄位 |
| `orca_noc_router.sv:106,174,199-203` | 4b，讀自 wire[495:492]（payload 內容），作 buffer index 與 rx_ready 選擇 | ❌ 與 pkg 語義脫節 |
| `stub_tiles.sv:33,41` | payload[491:488] 寫 vc、struct vc_id=0 | ❌ 落點錯 4 位（實效 VC=cnt[3:0]，常 ≥4 被丟） |
| `npu_tile_noc.sv:25,35` | vc_id=2'b00；只用 vc_credit[0] | ⚠ 單 VC 假設 |
| `orca_noc_link.sv:20,32` | 不用 flit vc_id；`|rx_credit` OR 約簡 | ⚠ 名為 4 VC 實為單一 credit |

結論：vc_id 全鏈路**不一致**；目前 SoC 層實際只有「由 payload 決定的單一倖存 VC」可用。修復方案必須把 vc 明確搬上線網。

---

## 3. 三個修復選項

### 3.1 選項 (a)：router 統一改用 `orca_pkg::flit_t`，線網 525b（刪私有型別）【推薦】

**設計**：router 刪除 `:94-110` 的私有 enum/struct，五組埠改為 `flit_t`（或 `logic [$bits(flit_t)-1:0]` = 525b）；buffer 陣列改 525b；`compute_route` 輸入改 2b（NOC_X/Y_BITS）。SoC mesh 線網全部 512b→525b。adapter 退化為 valid/ready 直通（或直接刪除、tile 直連 router local 埠）。

**位元級對齊圖**（每個 flit 自帶完整標頭，無偏移）：

```
wire[524:0] = { payload[511:0], dest_x[1:0], dest_y[1:0], src_x[1:0],
                src_y[1:0], vc_id[1:0], ftype[1:0], valid }
   524     13 12   11 10    9 8    7 6    5 4   3 2   1 0
```

**影響檔案**：
- `rtl/noc/orca_noc_router.sv`（刪私有型別；埠/內部訊號/buffer 改 flit_t 或 525b；compute_route 位寬；rx/tx assign 變同寬）
- `rtl/soc/orca_v63_soc.sv`（`:71-76` vn/vs/he/hw/ad_rx/ad_tx 及 `:102-107` 區域線網 512→525；刪除/替換 `:82-93` adapter 實例；移除 `:41,72,73,76` COV-EXEMPT 註解）
- `rtl/noc/orca_flit_adapter.sv`（退化直通或刪除；SPEC Workstream B 的 adapter 接入要求以直通形式保留亦可）
- `tb/cov_f5/orca_noc_router_cov_tb.sv`（DW 516→525；mkflit 改 pkg 布局；`:214-221` poke-blitz 的內部訊號名稱需保留）
- `tb/cov_f5/orca_flit_adapter_cov_tb.sv`（改寫或退役）
- `tb/cov_soc/stub_tiles.sv` / `stub_tiles_flood.sv`（移除 payload[495:488] 魔法位元，直接設 struct 欄位；vc_id 用真欄位）
- 不影響：`rtl/noc/orca_noc_link.sv`、`tb/noc_tb/orca_noc_tb.sv`（本就走 pkg flit_t）、`npu_tile_noc.sv`、`orca_v63_cpu_tile.sv`

**對 v6.3.3.2 已 100% 覆蓋的影響**：SoC 每條 mesh net +13 toggle 點（點數增加）；原豁免點（he_*、vn_v/vs_v[1..3]、ad_tx_v[1..3]、ct_iv/at_iv[1..3]）回到分母，**必須靠新 directed 測試命中否則 tgl_check 跌破 100%**；router 內部 buffer/訊號位寬改變 → toggle 點數移位，行號位移須重新審視行錨豁免註解。

**HBM3/CHI 相容性**：✅ 最佳。payload 512b 完整，body/tail flit 也攜帶 dest/vc → `npu_tile_noc` 的 HEAD+TAIL packet 兩拍都可正確路由，dma_wdata 512b 不截斷。

**風險**：線網最寬（525b，真實晶片面積/時序成本最高）；觸及檔案最多；SoC 全量 elaborate 在 3/4GB 機型 OOM 的限制不變（仍靠 stub tile）。**優點**：單一型別真相源，根除整類「私有結構 vs 線網」錯位 bug。

### 3.2 選項 (b)：線網加寬到 516b（遷就 router 私有 struct）

**設計**：SoC 線網 512→516b，router 例化 `DATA_WIDTH=516`；adapter 改為產出 router 516b 布局：
`{2'b0,dx, 2'b0,dy, 2'b0,sx, 2'b0,sy, 4'b0, 2'b0,vc, 12'b0, 6'b0,ftype, payload[471:0]}`。

**位元級對齊圖**：

```
wire[515:512] dest_x | [511:508] dest_y | [507:504] src_x | [503:500] src_y
wire[499:496] msg_type | [495:492] vc_id | [491:480] packet_id
wire[479:472] flit_type | [471:0] payload
```

**影響檔案**：`orca_v63_soc.sv`（線網 +4b、豁免註解移除）、`orca_flit_adapter.sv`（重寫編碼）、`orca_noc_router.sv`（僅例化參數；RTL 可零改動）、`tb/cov_soc/stub_tiles*.sv`、`tb/cov_f5/orca_flit_adapter_cov_tb.sv`。**`tb/cov_f5/orca_noc_router_cov_tb.sv` 已用 DW=516，幾乎不動**（`:4-10,37-41`）。

**覆蓋影響**：router 單元覆蓋原樣保留（最大優點）；SoC net +4 toggle 點；原豁免點回分母同 (a)。

**HBM3/CHI 相容性**：❌ 結構性缺陷。router struct payload 恆 472b，**所有** flit（含 body/tail）payload 上限 472b → 512b cache line / CHI data / `npu_tile_noc` 的 dma_wdata 512b 單 flit 放不下，需拆成兩 flit 或加寬 router payload 到 512（→ 556b 線網變體 (b')，更寬）。且 body/tail 無標頭問題依舊（router 對每 flit 查 dest_x/dest_y，raw 資料被當標頭）。

**風險**：改動最小但把「472b payload」這個私有格式凝固進 SoC 介面，長期債務最高；不推薦單獨採用。

### 3.3 選項 (c)：512b 線網 header 重映射（router/adapter 共用同一 map）

**設計**：線網維持 512b，明定 head 編碼（建議值，可調）：

```
wire[511:508] dest_x | [507:504] dest_y | [503:500] src_x | [499:496] src_y
wire[495:494] vc_id | [493:492] ftype | [491:0] payload[491:0]   (head)
body/tail: 需擇一 — (i) 每 flit 都帶 20b 標頭（payload 492b）；
           (ii) router 加 per-input-VC 路由鎖存（真 wormhole，body 滿載 512b）
```

router 以顯式 unpack/pack function 取代 struct cast（`:153-157,274-283`）；adapter 對稱改寫；SoC **線網完全不動**。

**影響檔案**：`orca_noc_router.sv`（解碼邏輯）、`orca_flit_adapter.sv`（重寫）、`tb/cov_f5/orca_noc_router_cov_tb.sv`（mkflit 改新 map、DW=512）、`tb/cov_f5/orca_flit_adapter_cov_tb.sv`、`tb/cov_soc/stub_tiles*.sv`；`orca_v63_soc.sv` 僅移除豁免註解。

**覆蓋影響**：SoC toggle 點數**不變**（位寬不變），僅原豁免點回分母；router 內部行覆蓋點隨解碼重寫而移位，總點數約略持平。三者中對既有覆蓋版圖擾動最小。

**HBM3/CHI 相容性**：⚠ 取決於子選項。(c-i) 每 flit 標頭 → payload 492b，512b 資料仍需拆包；(c-ii) wormhole 鎖存 → body 滿載 512b 相容，但 router 要新增 per-VC 狀態與 head/tail 狀態機，複雜度與驗證成本上升，且触及 v6.3.3.2 已 100% 的 router 內部行。

**風險**：map 需文件化為新介面規約（建議寫進 SPEC 與檔頭註解），否則三年後又是另一套「私有布局」；dest 欄位維持 4b 可支援 16×16，綽綽有餘。

### 3.4 比較表

| 維度 | (a) pkg flit_t / 525b | (b) 線網 516b | (c) 512b header 重映射 |
|---|---|---|---|
| 線網寬度 | 525b（+13） | 516b（+4） | 512b（不變） |
| payload 完整性 | 512b 全保留 | 472b（缺陷） | head 492b；body 視子選項 |
| body/tail 可路由 | ✅ 天然 | ❌ 未解決 | (c-ii) 才解決 |
| 型別真相源 | 單一（pkg） | 仍私有 struct | 顯式 map 文件 |
| router RTL 改動 | 中 | 幾乎零 | 中（+鎖存則大） |
| SoC 佈線改動 | 全部 net 改寬 | 全部 net 改寬 | 零 |
| router 單元 TB | 重寫 mkflit/DW | 幾乎不動 | 重寫 mkflit |
| 既有 100% 覆蓋風險 | 點數增加+移位 | 點數小增 | 擾動最小 |
| HBM3/CHI 512b 資料 | ✅ | ❌ 需拆包 | ⚠ (c-ii) ✅ |
| SPEC 相容（flit_t 不可改） | ✅ | ✅ | ✅ |
| 長期維護性 | 最佳 | 最差（凝固私有格式） | 中（依賴文件紀律） |

---

## 4. 修復後逐方向行為變化（以選項 (a) 為準；(b)(c) 等價）

| 方向 | 修復前 | 修復後 | 覆蓋點變化 |
|---|---|---|---|
| EAST | 永不觸發 | dest_x>X_POS 正確東送；he_v/he_r[x][y]（x<3）可翻轉 | 原豁免點回分母並可命中 |
| WEST | x>0 無差別西漂 | 僅 dest_x<X_POS 時西送 | hw_* 仍須 directed 測試保證命中（命中率下降屬正常） |
| NORTH | 僅 x=0、按真dest_x 誤判 | 正確按 dest_y>Y_POS、在正確 column 北送 | vn_v/vs_v[1..3] 變可達 |
| SOUTH | 僅 (0,1)→(0,0) 碰巧可用 | 正確按 dest_y<Y_POS | vs_* 全列可達 |
| LOCAL | 僅 x=0 列、(0,1) 誤投 (0,0) | 正確 (dest_x,dest_y) 投遞 | ad_tx_v/ct_iv/at_iv[1..3] 變可達 |
| VC | 實效 VC=payload 資料，≥4 被丟 | vc_id 2b（a）或 4b map（b/c）恆 < NUM_VC | buffer 寫入點 vc1..3 命中數上升 |

---

## 5. 推薦與理由

**推薦選項 (a)**，理由依序：

1. **根除根因而非修補症狀**：BUG-C 的本質是「同一條線上兩套私有 bit 布局」。(a) 讓全鏈路只剩 `orca_pkg::flit_t` 一套布局，此類錯位不可能復發；(b)/(c) 都保留「線網編碼 ≠ 型別」的雙布局結構。
2. **唯一同時修好 body/tail 路由的方案**（§2.5）：每個 flit 自帶 dest/vc/valid，router 無需新增 wormhole 狀態，`npu_tile_noc` 的 HEAD+TAIL DMA packet 立即正確。
3. **HBM3/CHI 512b payload 零損失**：(b) 的 472b 是功能缺陷、(c-i) 的 492b 是頻寬損失，(a) 無此問題。
4. SPEC 已禁止改 pkg flit_t（SPEC-v633.md:15），(a) 順勢而為；(b) 反而把私有格式升格為 SoC 介面標準，方向相反。

代價（525b 線網、TB 改寫、覆蓋點增加）可接受：此為 RTL 模擬階段的架構修正，且 v6.3.4 本就規劃重做 SoC 層豁免項。**若工程上堅持線網 512b 不變，退而求其次採 (c-ii)**，並把 wire map 寫入 SPEC。

## 6. 實作步驟草案（選項 (a)）

1. **規約凍結**：在 SPEC 增補「NoC 線網 = $bits(flit_t) = 525b，欄位序依 orca_pkg.sv:233-242」；禁止模組內再定義 flit 結構（lint 規則或 code-review checklist）。
2. `rtl/noc/orca_noc_router.sv`：刪 `:94-110` 私有型別；埠與內部訊號/buffer 改 flit_t（或 `logic [524:0]`）；`compute_route` 改吃 2b dest_x/dest_y；`flit.vc_id` 2b 直接用；保留 `buf_wr_ptr/buf_rd_ptr/port_granted/port_requested/vc_requested/buf_count/output_port_busy` 等訊號名（router cov TB poke-blitz 依賴）。
3. `rtl/soc/orca_v63_soc.sv`：`:71-76,102-107` 全部 512b→525b；adapter 實例改直通或刪除（tile flit_t 直連 local 埠）；移除 `:41,72,73,76` 豁免註解。
4. `rtl/noc/orca_flit_adapter.sv`：退化為 valid/ready 直通（保留模組以維持介面層次，或直接刪除並更新 SoC）。
5. TB 更新：`orca_noc_router_cov_tb`（DW=525、mkflit 用 pkg 布局、斷言 data 一致性）；`orca_flit_adapter_cov_tb`（改直通檢查或退役）；`stub_tiles*.sv`（移除 payload 魔法位元、用 struct 欄位、vc_id 真值 0~3）。
6. 修正 stub 註解中 vc 落點的錯誤認知（§1.5），避免再次誤導。
7. lint：soc+noc 子集 lint 0 error（沿用 SPEC 的 3GB 限制流程）。
8. 全量回歸：43 組 coverage TB + soc_flood + SVA，並重跑 `scripts/tgl_check.py` 六前綴，目標 line/toggle 維持 100%（新回分母的點須由 §7 測試命中）。

### 7. 驗收測試建議（SoC 層 directed）

1. **EAST 單跳**：於 R(0,0) local 注入 dest=(1,0)，檢查 `he_v[0][0]` 拉起、R(1,0) west_rx 收到、最終 `ct_iv[1]`/`at_iv[1]` 投遞且 payload 逐位相等。
2. **EAST 多跳**：dest=(3,1) 自 (0,0)，路徑 E→E→E→N，驗證每跳 he/vn 握手與端點投遞、總延遲上界。
3. **全對全矩陣**：8 tile × 8 tile 共 64 組 src→dst，scoreboard 於各 tile noc_in 比對 payload 與順序；涵蓋 E/W/N/S/LOCAL 五類。
4. **VC 掃描**：每方向以 vc_id=0..3 注入，確認無越界丟棄、各 VC buffer 獨立。
5. **Backpressure**：中途拉低 tx_ready，驗證 flit 留存不複製不遺失（沿用 router cov TB `:105-121` 手法上移到 SoC 層）。
6. **多 flit packet**：以 `npu_tile_noc` HEAD+TAIL 模式送 512b dma_wdata，驗證 TAIL 跟隨 HEAD 路由且資料完整（HBM3 路徑迴歸）。
7. **邊界丟棄檢查**：dest 超出 4×2 mesh 時不得有 flit 從 tie-off 邊界「被吸收而無聲丟棄」（加 SVA 計數）。
8. **SVA bind**：assert adapter 兩側 dest_x/dest_y/vc_id 守恆；assert router rx 端 `$bits(rx_data)==$bits(flit_t)`。

---

## 附：關鍵證據索引

- pkg flit_t 定義（525b）：`rtl/common/orca_pkg.sv:233-242`；位寬參數 `:89-94`
- router 私有 flit_t（516b）與檔頭錯註解：`rtl/noc/orca_noc_router.sv:87-110`
- EAST 分支：`rtl/noc/orca_noc_router.sv:134-135`；struct 零填充接入 `:153-157`；vc buffer 索引 `:174,199-203`
- adapter 編碼：`rtl/noc/orca_flit_adapter.sv:23-36`
- SoC 512b 線網與豁免註解：`rtl/soc/orca_v63_soc.sv:41,70-76,100-172`
- stub 對齊實證（含 vc 落點誤差）：`tb/cov_soc/stub_tiles.sv:29-43`、`stub_tiles_flood.sv` 同構
- router 單元 TB（DW=516 已知私有寬度）：`tb/cov_f5/orca_noc_router_cov_tb.sv:4-10,37-41`
- 多 flit packet 來源：`rtl/ai/noc/npu_tile_noc.sv:31-36`
- SPEC 型別凍結：`SPEC-v633.md:15`；v6.3.3.2 根因節：`orca_v63_v6332_report.md:81,95`
