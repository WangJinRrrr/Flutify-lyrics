# 按 HLS byterange 下载完整音频并拼装（policy 3 = METHOD=NONE）。
import json, os, re, sys, urllib.request

m3u8_path = sys.argv[1] if len(sys.argv) > 1 else r'D:\tmp\hls3.m3u8'
out_path = sys.argv[2] if len(sys.argv) > 2 else r'D:\tmp\full_audio.mp4'
text = open(m3u8_path, encoding='utf-8').read()

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))

# 解析 EXT-X-MAP 与 EXT-X-BYTERANGE 序列
entries = []
cur_url = None
map_uri = None
map_range = None
lines = text.splitlines()
i = 0
pending_range = None
while i < len(lines):
    line = lines[i].strip()
    if '#EXT-X-MAP:' in line:
        m = re.search(r'#EXT-X-MAP:URI="([^"]+)".*?BYTERANGE="(\d+)@(\d+)"', line)
        if m:
            map_uri, map_len, map_off = m.group(1), int(m.group(2)), int(m.group(3))
            entries.append((map_uri, map_off, map_len))
    elif '#EXT-X-BYTERANGE:' in line:
        m = re.search(r'#EXT-X-BYTERANGE:(\d+)@(\d+)', line)
        pending_range = (int(m.group(1)), int(m.group(2)))
    elif line.startswith('https://') or line.startswith('http://'):
        if pending_range:
            entries.append((line, pending_range[1], pending_range[0]))
            pending_range = None
    i += 1

print('%d byte-ranges, total %d B' % (len(entries), sum(e[2] for e in entries)))
with open(out_path, 'wb') as out:
    for n, (url, off, ln) in enumerate(entries):
        req = urllib.request.Request(url, headers={'Range': 'bytes=%d-%d' % (off, off + ln - 1)})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
        out.write(data)
        print('seg %d: %d B (want %d)' % (n, len(data), ln))
print('saved ->', out_path)
