#!/usr/bin/env python3
# tgl_check.py <rtl路徑前綴1> [前綴2 ...] — 檢查指定 rtl 檔群的 v_toggle 零命中點
# 例: python3 /mnt/agents/output/tgl_check.py rtl/cpu/execution rtl/cpu/rename
import glob, re, collections, sys
pat = re.compile(r"C '\x01f\x02([^\x01]+)\x01l\x02(\d+)\x01n\x02\d+\x01page\x02([a-z_]+)/([^\x01]+)\x01o\x02([^\x01]+)\x01h\x02([^']*)' (\d+)")
prefixes = sys.argv[1:] or ['rtl/']
sigsum = collections.defaultdict(int)
dats = sorted(glob.glob('/mnt/agents/output/orca_v63_package/build/cov_final/*/coverage.dat'))
for d in dats:
    for m in pat.finditer(open(d,'rb').read().decode('latin1')):
        f,l,typ,hmod,sig,hier,cnt = m.groups()
        if typ=='v_toggle' and any(f.startswith(p) for p in prefixes):
            sigsum[(f,sig)] += int(cnt)
zero = sorted(k for k,v in sigsum.items() if v==0)
tot = len(sigsum)
print(f"範圍 {prefixes}: v_toggle 點 {tot}, 0-hit {len(zero)}, 覆蓋率 {(tot-len(zero))/max(tot,1)*100:.2f}%")
byf = collections.Counter(f for f,s in zero)
for f,c in byf.most_common():
    print(f"  {c:>6}  {f}")
if zero:
    print("\n--- 前 40 個零命中點 ---")
    for f,s in zero[:40]: print(f"  {f} :: {s}")
sys.exit(1 if zero else 0)
