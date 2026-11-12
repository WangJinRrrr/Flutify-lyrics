# 逆向实测：track-playback/v1/media + manifests/v9（xpui.js getManifest / o() 的真实实现）。
import json, os, sys, urllib.request, urllib.error

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
token = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']

H = {
    'Authorization': 'Bearer ' + token,
    'client-token': ctok,
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    'app-platform': 'Win32_x86_64',
    'Accept': 'application/json',
}

uri = sys.argv[1] if len(sys.argv) > 1 else 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b'
fid = '4b47b6d3c1de4b23187c52032ad9904e6e5a9010'

tests = [
    ('track-playback uri', 'https://spclient.wg.spotify.com/track-playback/v1/media/%s?manifestFileFormat=3' % uri),
    ('track-playback gid', 'https://spclient.wg.spotify.com/track-playback/v1/media/1e6028dab84d4a17a1b3fb28ad51df5d?manifestFileFormat=3'),
    ('manifests v9 fid', 'https://spclient.wg.spotify.com/manifests/v9/json/sources/%s/options/supports_drm' % fid),
    ('manifests v9 aid', 'https://spclient.wg.spotify.com/manifests/v9/json/sources/fb294b68b1514ec12aa50fe0d77accf9/options/supports_drm'),
]

for desc, url in tests:
    req = urllib.request.Request(url, headers=H)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read()
            print('==', desc, 'HTTP', r.status, len(data), 'B')
            try:
                j = json.loads(data)
                print(json.dumps(j, indent=1, ensure_ascii=False)[:2500])
            except Exception:
                print(data[:400])
    except urllib.error.HTTPError as e:
        print('==', desc, 'HTTP', e.code, e.read()[:200])
