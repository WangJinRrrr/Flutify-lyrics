import re, sys
data = open(r'C:\Users\ZhaoYunFeng\AppData\Roaming\Spotify\Spotify.dll', 'rb').read()
pat = sys.argv[1].encode()
span = int(sys.argv[2]) if len(sys.argv) > 2 else 1800
out = []
for m in re.finditer(re.escape(pat), data):
    s = max(0, m.start() - 200)
    e = min(len(data), m.end() + span)
    chunk = data[s:e]
    txt = re.sub(rb'[^ -~]{3,}', b'|', chunk)
    out.append(hex(m.start()) + '\n' + txt.decode('ascii', 'replace'))
open(r'D:\tmp\ctx.txt', 'w', encoding='utf-8').write('\n=====\n'.join(out))
print(len(out), 'matches')
