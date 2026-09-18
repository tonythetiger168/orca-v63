import sys, subprocess, re
# usage: f3_check.py file1 file2 ... -- dat1 dat2 ...
args = sys.argv[1:]
sep = args.index('--')
files, dats = args[:sep], args[sep+1:]
info = subprocess.run(['verilator_coverage','--write-info','/dev/stdout']+dats,
                      capture_output=True, text=True).stdout
cur = None; data = {}
for line in info.splitlines():
    if line.startswith('SF:'): cur = line[3:]; data[cur] = {}
    elif line.startswith('DA:') and cur:
        n, h = line[3:].split(',')[:2]
        data[cur][int(n)] = int(h)
for f in files:
    match = [k for k in data if k.endswith(f)]
    if not match: print(f"{f}: NOT FOUND"); continue
    d = data[match[0]]
    zero = sorted(n for n, h in d.items() if h == 0)
    print(f"{f}: {len(d)-len(zero)}/{len(d)} covered; zero={zero}")
