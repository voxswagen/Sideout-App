import io, re, subprocess, sys
P='/Users/angelopaolodequina/Documents/GitHub/Sideout-App/index.html'

def parses():
    s = io.open(P, encoding='utf-8').read()
    b = re.findall(r'<script>(.*?)</script>', s, re.S)
    io.open('/tmp/chk.js','w',encoding='utf-8').write(b[1])
    return subprocess.run(['node','--check','/tmp/chk.js'],
                          capture_output=True).returncode == 0

def dead_funcs(s):
    lines = s.split('\n')
    defs = {}
    for i, ln in enumerate(lines):
        m = re.match(r'^(?:async )?function ([A-Za-z_$][\w$]*)\s*\(', ln)
        if m: defs.setdefault(m.group(1), i)
    out = []
    for name, i in defs.items():
        n = len(re.findall(r'(?<![\w$.])' + re.escape(name) + r'(?![\w$])', s))
        if n <= 1: out.append((name, i))
    return sorted(out, key=lambda x: x[1])

def span(lines, i):
    """A top-level function ends on the first line that is exactly '}'."""
    for j in range(i+1, len(lines)):
        if lines[j] == '}': return j
    return None

total_lines = 0; total_fns = 0; rounds = 0
while True:
    s = io.open(P, encoding='utf-8').read()
    dead = dead_funcs(s)
    if not dead: break
    rounds += 1
    lines = s.split('\n')
    spans = []
    for name, i in dead:
        j = span(lines, i)
        if j is None: continue
        # the block must contain its own definition and nothing else top-level
        body = lines[i:j+1]
        if sum(1 for b in body[1:] if re.match(r'^(?:async )?function ', b)): continue
        spans.append((i, j, name))
    if not spans: break
    # keep a copy, then cut descending
    io.open('/tmp/index.bak.html','w',encoding='utf-8').write(s)
    for i, j, name in sorted(spans, key=lambda x: -x[0]):
        del lines[i:j+1]
        total_lines += (j - i + 1); total_fns += 1
    io.open(P,'w',encoding='utf-8').write('\n'.join(lines))
    if not parses():
        io.open(P,'w',encoding='utf-8').write(io.open('/tmp/index.bak.html',encoding='utf-8').read())
        print('round %d broke the parse — reverted that round' % rounds)
        break
    print('round %d: removed %d functions' % (rounds, len(spans)))
print('TOTAL: %d functions, %d lines' % (total_fns, total_lines))
