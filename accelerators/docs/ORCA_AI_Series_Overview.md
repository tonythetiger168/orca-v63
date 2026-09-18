# ORCA AI Accelerator Series — 全系列設計總覽
**版本**: v1.2  **日期**: 2026-09-05  **作者**: ORCA Architecture Team
---

## 產品線定位
| 世代 | 代號 | 定位 | 峰值算力 | 製程目標 | 核心技術 |
|:---|:---|:---|:---|:---|:---|
| v5.0 X | **Kestrel** | 輕量級邊緣 AI | **1 TOPS** | 22nm / 1GHz | 8-MAC 陣列 + INT8/INT16 |
| v5.1 X+ | **Falcon** | 向量加速 AI | **4 TOPS** | 12nm / 1.5GHz | RVV 1.0 + 32×32 脈動陣列 (FMX) |
| v5.2 X++ | **Hawk** | 高效能邊緣 AI / 輕量伺服器 | **8 TOPS** | 7nm / 2.0GHz | RVV-256 + 4×32×32 脈動陣列 (FMX2) + Transformer 硬加速 |
| v6.0 ZEN | **Phoenix** | 旗艦級 AI | **16 TOPS** | 5nm / 3.2GHz | TPE 張量引擎 + AME 自適應矩陣引擎 |
| **v6.1 ZEN** | **Phoenix-E** | **邊緣伺服器 / 高階 IPC** | **12 TOPS** | **7nm / 2.5GHz** | **Phoenix 降規版 (6 tiles + CHI 256-bit)** |
| **v6.2 ZEN** | **Phoenix+** | **資料中心 / 大規模推理** | **32 TOPS** | **5nm / 3.2GHz ×2** | **雙晶片 UCIe (2×Phoenix)** |

---

## 架構演進路線
```
v5.0 Kestrel (1 TOPS) ──→ v5.1 Falcon (4 TOPS) ──→ v5.2 Hawk (8 TOPS)
    8 MACs                    2×32×32 MACs              4×32×32 MACs
    AXI4 64-bit               AXI4 128-bit              AXI4 256-bit
    INT8/16                   INT8/16/FP16/BF16         +FP32/Transformer
        ↓
v6.0 Phoenix (16 TOPS) ──→ v6.1 Phoenix-E (12 TOPS) ──→ v6.2 Phoenix+ (32 TOPS)
    TPE 8 tiles               TPE 6 tiles (降規)          2× TPE 8 tiles (UCIe)
    AME 16 blocks             AME 12 blocks (降規)
        2× AME 16 blocks
    CHI 512-bit               CHI 256-bit (降規)          2× CHI 512-bit + D2D
```

---

## 性能對比總表
| 指標 | v5.0 Kestrel | v5.1 Falcon | v5.2 Hawk | v6.0 Phoenix | **v6.1 Phoenix-E** | **v6.2 Phoenix+** |
|:---|:---|:---|:---|:---|:---|:---|
| **峰值算力 (INT8)** | 1 TOPS | 4 TOPS | 8 TOPS | 16 TOPS | **12 TOPS** | **32 TOPS** |
| **精度支持** | INT8/INT16 | INT8/INT16/FP16/BF16 | INT8/INT16/FP16/BF16/FP32 | INT8/FP16/BF16/FP32 | **INT8/FP16/BF16/FP32** | **INT8/FP16/BF16/FP32** |
| **製程** | 22nm | 12nm | 7nm | 5nm | **7nm** | **5nm** |
| **頻率** | 1.0 GHz | 1.5 GHz | 2.0 GHz | 3.2 GHz | **2.5 GHz** | **3.2 GHz** |
| **功耗** | <150 mW | <800 mW | <3 W | <15 W | **<8 W** | **<30 W** |
| **面積估計** | 0.3 mm² | 1.8 mm² | 3.5 mm² | 8.5 mm² | **~6.3 mm²** | **2×8.5 mm²** |
| **MAC 數量** | 8 | 2,048 | 4,096 | 3,072 | **2,304** | **6,144** |
| **稀疏加速** | 無 | 無 | 無 | 2:4 結構化 (AME) | **2:4 結構化 (AME)** | **2:4 結構化 (AME)** |
| **Transformer** | 不適用 | 小模型 (<10M) | BERT/GPT-2/ViT | LLM (Qwen3, DeepSeek) | **LLM (Qwen3, DeepSeek)** | **LLM (Qwen3, DeepSeek)** |
| **記憶體介面** | AXI4 64-bit | AXI4 128-bit | AXI4 256-bit | CHI.E/F 512-bit | **CHI 256-bit** | **2× CHI 512-bit + UCIe** |
| **軟體棧** | TFLite Micro | ONNX Runtime + RVV | PyTorch Edge + ONNX | PyTorch 2.0 + Triton | **PyTorch 2.0 + Triton** | **PyTorch 2.0 + Triton** |
| **ISA 相容** | — | — | — | WMMA + SpMM | **WMMA + SpMM (同 v6.0)** | **WMMA + SpMM (同 v6.0)** |

---

## 目錄結構
```
orca_ai_accelerators/
├── v5_0_kestrel/
│   ├── rtl/orca_npu_v5.sv
│   ├── docs/Kestrel_Architecture.md
│   └── integration/orca_soc_top_v5_npu.sv
├── v5_1_falcon/
│   ├── rtl/orca_npu_v5_1.sv
│   ├── docs/Falcon_Architecture.md
│   └── integration/orca_soc_top_v5_1_npu.sv
├── v5_2_hawk/
│   ├── rtl/orca_npu_v5_2.sv
│   ├── docs/Hawk_Architecture.md
│   └── integration/orca_soc_top_v5_2_npu.sv
├── v6_0_phoenix/
│   ├── rtl/orca_tpe_v6.sv
│   ├── rtl/orca_ame_v6.sv
│   ├── docs/Phoenix_Architecture.md
│   └── integration/orca_soc_top_v6_npu.sv
├── v6_1_phoenix_e/                          # ← 新增
│   ├── rtl/orca_tpe_v6_1.sv
│   ├── rtl/orca_ame_v6_1.sv
│   ├── docs/Phoenix_E_Architecture.md
│   └── integration/orca_soc_top_v6_1_npu.sv
├── v6_2_phoenix_plus/                       # ← 新增
│   ├── rtl/orca_tpe_v6_2.sv
│   ├── rtl/orca_ame_v6_2.sv
│   ├── docs/Phoenix_Plus_Architecture.md
│   └── integration/orca_soc_top_v6_2_npu.sv
├── docs/
│   ├── ORCA_AI_Series_Overview.md
│   ├── THead_vs_ORCA_AI_Comparison.md
│   └── Software_Stack.md
├── scripts/
│   └── build_all.sh
└── tb/
```

---

## 設計原則
1. **開源優先**: 所有 RTL 採用 SystemVerilog，Apache 2.0 授權
2. **軟體相容**: 從 1 TOPS 到 32 TOPS 統一編程模型，無縫遷移
3. **標準合規**: RVV 1.0 完整合規，自定義擴展使用 RISC-V reserved opcode space
4. **可配置性**: 所有參數化設計，可根據目標應用縮放
5. **連續演進**: v5.x 系列共享相同基礎架構，v6.x 系列共享 WMMA+SpMM ISA
6. **晶片化擴展**: Phoenix+ 通過 UCIe 實現線性擴展，無需重新設計矽晶片
