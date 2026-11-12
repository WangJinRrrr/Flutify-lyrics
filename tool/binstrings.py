import re, sys
path = sys.argv[1]
pat = sys.argv[2].lower()
maxn = int(sys.argv[3]) if len(sys.argv) > 3 else 60
data = open(path, 'rb').read()
n = 0
for m in re.finditer(rb'[\x20-\x7e]{4,}', data):
    s = m.group().decode()
    if pat in s.lower():
        print(hex(m.start()), s[:300])
        n += 1
        if n >= maxn:
            break
