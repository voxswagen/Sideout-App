import io, re, sys
p='/Users/angelopaolodequina/Documents/GitHub/Sideout-App/index.html'
s = io.open(p, encoding='utf-8').read()
lines = s.split('\n')
# top-level function declarations only (column 0)
defs = {}
for i, ln in enumerate(lines):
    m = re.match(r'^(?:async )?function ([A-Za-z_$][\w$]*)\s*\(', ln)
    if m: defs.setdefault(m.group(1), i)
dead = []
for name, i in defs.items():
    n = len(re.findall(r'(?<![\w$.])' + re.escape(name) + r'(?![\w$])', s))
    if n <= 1: dead.append((name, i+1, n))
dead.sort(key=lambda x: x[1])
print('top-level functions:', len(defs), '  referenced nowhere else:', len(dead))
for name, ln, n in dead: print('  %-28s line %-7d refs:%d' % (name, ln, n))
