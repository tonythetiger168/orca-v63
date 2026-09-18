# ORCA Phoenix+ — 2.5
D CoWoS Package Planning
**Version**: 1.0  **Date**: 2026-09-05  **Target**: TSMC CoWoS-S / Intel EMIB / Samsung I-Cube
---

## 1. Package Overview
Phoenix+ uses a **2.5D chiplet integration** approach to achieve 32 TOPS without redesigning the Phoenix v6.0 silicon. Two identical Phoenix dies are placed on a silicon interposer and connected via UCIe.
```
+---------------------------------------------------------------+
|                    Organic Substrate (55×55 mm)               |
|                                                               |
|   +-----------------------------------------------------+     |
|   |              Silicon Interposer (~25×15 mm)           |     |
|   |                                                     |     |
|   |    +----------+         +----------+                |     |
|   |    | Phoenix  |=========| Phoenix  |                |     |
|   |    | Die 0    |  UCIe   | Die 1    |                |     |
|   |    | 8.5 mm²  | 256-bit | 8.5 mm²  |                |     |
|   |    |          | 16 GT/s |          |                |     |
|   |    +----+-----+         +----+-----+                |     |
|   |         |                    |                      |     |
|   |    +----+-----+         +----+-----+                |     |
|   |    | HBM3/    |         | HBM3/    |                |     |
|   |    | DDR5 PHY |         | DDR5 PHY |                |     |
|   |    +----------+         +----------+                |     |
|   +-----------------------------------------------------+     |
|          |                           |                        |
|    +-----+-----+               +-----+-----+                  |
|    | DDR5-6400 |               | DDR5-6400 |                  |
|    | 2x40-bit  |               | 2x40-bit  |                  |
|    +-----------+               +-----------+                  |
+---------------------------------------------------------------+
```

---

## 2. Die Floorplan
### 2.1 Single Phoenix Die (8.5 mm²)
```
+---------------------------------------------------+
|  3.0 mm                                           |
|                                                   |
|  +---------------------+  +---------------------+ |
|  |      TPE Engine     |  |      AME Engine     | |
|  |  8 tiles × 16×16    |  |  16 blocks × 8×8    | |
|  |  ~5.5 mm²           |  |  ~1.5 mm²           | |
|  +---------------------+  +---------------------+ |
|  |  SRAM: 96KB (TPE)   |  |  SRAM: 48KB (AME)   | |
|  +---------------------+  +---------------------+ |
|                                                   |
|  +-----------------------------------------------+ |
|  |         CHI NoC + DDR5 PHY (~1.5 mm²)         | |
|  +-----------------------------------------------+ |
|  |  UCIe PHY (北側邊緣, ~0.5 mm²)                | |
|  +-----------------------------------------------+ |
+---------------------------------------------------+
```

### 2.2 UCIe Bump Map (北側邊緣)
```
Signal      | Count | Pitch  | Notes
------------|-------|--------|--------------------------
d2d_tx_data  | 256   | 40 um  | TX 數據 (Die 0 → Die 1)
d2d_tx_valid | 1     | 40 um  | TX 有效
d2d_tx_ready | 1     | 40 um  | TX 就緒
d2d_rx_data  | 256   | 40 um  | RX 數據 (Die 1 → Die 0)
d2d_rx_valid | 1     | 40 um  | RX 有效
d2d_rx_ready | 1     | 40 um  | RX 就緒
VDD_UCIe   | 32    | 80 um  | UCIe 電源
VSS_UCIe   | 32    | 80 um  | UCIe 地線
------------|-------|--------|--------------------------
Total       | 580   |        | 佔用面積 ~0.5 mm²
```

---

## 3. Interposer Design
### 3.1 Routing Layers
| Layer | Material | Width/Space | Purpose |
|:---|:---|:---|:---|
| M1 (底部) | Cu | 0.5/0.5 um | 電源分配 (VDD/VSS) |
| M2 | Cu | 0.4/0.4 um | 信號路由 (UCIe data) |
| M3 | Cu | 0.4/0.4 um | 信號路由 (UCIe control) |
| M4 (頂部) | Cu | 1.0/1.0 um | 再分佈層 (RDL) |

### 3.2 UCIe Trace Specification
| Parameter | Value | Notes |
|:---|:---|:---|
| Trace Length | < 5 mm | Die edge to die edge |
| Trace Width | 0.4 um | Interposer M2/M3 |
| Trace Spacing | 0.4 um | Differential pairs |
| Characteristic Impedance | 50 Ω ± 5% | Single-ended |
| Insertion Loss @ 8 GHz | < 1 dB | 16 GT/s NRZ |
| Crosstalk | < -30 dB | NEXT/FEXT |

---

## 4. Thermal Design
### 4.1 Power Map
| Component | Die 0 | Die 1 | Total |
|:---|:---|:---|:---|
| TPE | ~10 W | ~10 W | ~20 W |
| AME | ~2.5 W | ~2.5 W | ~5 W |
| DDR5 PHY | ~1 W | ~1 W | ~2 W |
| UCIe PHY | ~0.5 W | ~0.5 W | ~1 W |
| **Total** | **~14 W** | **~14 W** | **~28 W** |

### 4.2 Thermal Solution
```
Ambient 25°C
    │
    ▼

+---------------+
|  Heatsink     |  ← Vapor chamber, 200 W capacity

+---------------+

    │
    ▼

+---------------+
| TIM (15 μm)   |  ← Thermal grease, 3 W/mK

+---------------+

    │
    ▼

+---------------+
| Lid (Cu)      |  ← 2 mm thick

+---------------+

    │
    ▼

+---------------+
| Underfill     |  ← CTE matched

+---------------+

    │
    ▼

+---------------+
| Interposer    |
+---------------+
    │
    ▼

+---------------+
| Substrate     |
+---------------+
```
**預估結溫**: ~85°C @ 28W (有散熱器), ~105°C @ 28W (無風扇)
---

## 5. Signal Integrity Simulation
### 5.1 UCIe Channel Model
```
[Die 0 TX] ──→ [Bump] ──→ [RDL] ──→ [Interposer M2] ──→ [RDL] ──→ [Bump] ──→ [Die 1 RX]
     ↑
                    ↑
                      ↑
                      ↑   C_bump=20fF
      L_bump=50pH         R_trace=0.1Ω/mm
      C_bump=20fF
```

### 5.2 Eye Diagram Requirements
| Parameter | Specification | Simulated | Margin |
|:|:---|:---|:---|
| Eye Height | > 200 mV | 280 mV | +80 mV ✅ |
| Eye Width | > 0.6 UI | 0.72 UI | +0.12 UI ✅ |
| Jitter (RMS) | < 0.05 UI | 0.03 UI | +0.02 UI ✅ |
| BER | < 1e-15 | ~1e-18 | Pass ✅ |

---

## 6. Assembly Flow
1. **晶圓測試**: Phoenix die KGD (Known Good Die) 篩選
2. **Interposer 製造**: TSMC CoWoS-S 流程 (65nm 邏輯層)
3. **微凸塊 (μBump)**: Cu pillar, 40 μm pitch
4. **晶片貼裝**: TCB (Thermo-Compression Bonding), 300°C
5. **底部填充**: Capillary underfill, CTE 25 ppm/°C
6. **RDL 與 C4 凸塊**: 有機基板上再分佈
7. **最終測試**: 功能 + 老化 + 熱循環
---

## 7. Cost Estimate
| Item | Unit Cost | Notes |
|:|:---|:---|
| Phoenix Die (×2) | $80 × 2 | 5nm, 8.5 mm², yield ~85% |
| Interposer | $45 | 65nm, 25×15 mm |
| Organic Substrate | $15 | 14-layer, 55×55 mm |
| HBM3 (optional) | $120 | 2× 8GB stacks |
| Assembly + Test | $25 | CoWoS-S 流程 |
| **Total BOM** | **~$365** | 不含 HBM: ~$245 |
| **vs H100 ($30K)** | **~1.2%** | 60× 成本優勢 |

---

## 8. Reliability
| Test | Condition | Requirement | Status |
|:|:---|:---|:---|
| TCT | -55°C ~ 125°C, 1000 cycles | 電阻變化 < 10% | 待驗證 |
| HTST | 150°C, 1000 hours | 功能正常 | 待驗證 |
| uHAST | 130°C/85%RH, 96 hours | 無腐蝕 | 待驗證 |
| Vibration | 20G, 20-2000 Hz | 無結構損傷 | 待驗證 |
