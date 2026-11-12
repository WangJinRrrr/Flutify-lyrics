# Brute-force which track id produced the cached lyrics key sha1('v3|'+id).
import hashlib
import json
import os
import re

target = '52f565a32c56047cccbad45c460e66918baac55b'
prefs = json.load(open(os.path.expandvars(r'%APPDATA%\com.flutify.music\flutify_app\shared_preferences.json'), encoding='utf-8'))

text = json.dumps(prefs)
ids = set(re.findall(r'spotify:track:([0-9A-Za-z]{22})', text))
# also bare ids in track objects
ids |= set(re.findall(r'"id"\s*:\s*"([0-9A-Za-z]{22})"', text))
print('candidate ids:', len(ids))

found = None
for i in ids:
    if hashlib.sha1(('v3|' + i).encode()).hexdigest() == target:
        found = i
        break
print('match:', found)

if found:
    # find the track object with this id
    m = re.search(r'\{[^{}]*"id"\s*:\s*"' + found + r'"[^{}]*\}', text)
    if m:
        print(m.group(0)[:600])
