import sys, collections
def parse(dat):
    for line in open(dat, errors='replace'):
        if not line.startswith('C '): continue
        body, cnt = line[3:].rsplit("'", 1)
        toks = [t for t in body.split('\x01') if t != '']
        d = {}
        for t in toks:
            if '\x02' in t:
                k, v = t.split('\x02', 1)
                d[k] = v
        d['_cnt'] = int(cnt)
        yield d
def points(dat, specs):
    want = collections.defaultdict(set)
    for s in specs.split(','):
        f, l = s.rsplit(':', 1); want[f].add(int(l))
    agg = collections.defaultdict(list)
    for d in parse(dat):
        base = d.get('f','').split('/')[-1]
        if not base: continue
        l = int(d['l'])
        if base in want and l in want[base]:
            agg[(base,l)].append((d['page'].split('/')[0], d.get('o','').strip(), d['_cnt']))
    for (b, l) in sorted(agg):
        kinds = collections.Counter()
        for kind, o, cnt in agg[(b,l)]:
            kinds[(kind, cnt > 0)] += 1
        print(f"{b}:{l} " + ", ".join(f"{k}({'hit' if h else 'zero'})x{n}" for (k,h),n in kinds.items()))
if __name__ == '__main__':
    points(sys.argv[1], sys.argv[2])
