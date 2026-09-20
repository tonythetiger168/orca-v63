import sys
targets = [
  "rtl/ai/attention/npu_attn_engine.sv",
  "rtl/ai/cluster/npu_cluster.sv",
  "rtl/ai/cluster/npu_cu.sv",
  "rtl/ai/ctrl/npu_aix_intf.sv",
  "rtl/ai/ctrl/npu_dma.sv",
  "rtl/ai/ctrl/npu_gscu.sv",
  "rtl/ai/memory/npu_hbm3_ctrl.sv",
  "rtl/ai/memory/npu_hbm3_phy.sv",
  "rtl/ai/memory/npu_l2_sram.sv",
  "rtl/ai/noc/npu_tile_noc.sv",
  "rtl/ai/orca_v63_ai_tile.sv",
  "rtl/ai/pe/npu_pe.sv",
  "rtl/ai/pe/npu_systolic.sv",
]
sf = None; holes = {}; tot = {}
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line.startswith("SF:"): sf = line[3:]
        elif line.startswith("DA:") and sf:
            p = line[3:].split(","); ln, hits = int(p[0]), int(p[1])
            for t in targets:
                if sf.endswith(t):
                    tot[t] = tot.get(t, 0) + 1
                    if hits == 0: holes.setdefault(t, []).append(ln)
        elif line == "end_of_record": sf = None
ok = True
for t in targets:
    h = holes.get(t, []); n = tot.get(t, 0)
    if n == 0: print("MISSING(no points): %s" % t); ok = False
    elif h: print("HOLES %-45s: %s" % (t, h)); ok = False
    else: print("100%% (%d lines): %s" % (n, t))
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
