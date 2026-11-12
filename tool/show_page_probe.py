# 看单集页 initialState 里 Episode 实体的 podcastV2 结构。
import base64
import json
import re
import urllib.request

req = urllib.request.Request(
    'https://open.spotify.com/episode/4ar2L3XOkq9IT8ezkHd8vP',
    headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
)
html = urllib.request.urlopen(req, timeout=30).read().decode('utf-8', 'ignore')
m = re.search(r'<script id="initialState"[^>]*>(.*?)</script>', html, re.S)
data = json.loads(base64.b64decode(m.group(1).strip()).decode('utf-8', 'ignore'))
items = data['entities']['items']
print('keys:', list(items.keys()))
ep = items.get('spotify:episode:4ar2L3XOkq9IT8ezkHd8vP')
print('episode keys:', sorted(ep.keys()))
pv = ep.get('podcastV2')
print('podcastV2:', json.dumps(pv, ensure_ascii=False)[:600])
print('showOrAudiobook:', json.dumps(ep.get('showOrAudiobook'), ensure_ascii=False)[:600])
