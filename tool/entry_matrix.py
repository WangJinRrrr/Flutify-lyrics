# 逆向实测：sneaktables HLS / storage-resolve v2 / padme 入口矩阵。
# audio_id 来自 extended-metadata kind=5 AudioFilesExtensionResponse 头部。
import json, os, urllib.request, urllib.error

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
token = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']

fid = '4b47b6d3c1de4b23187c52032ad9904e6e5a9010'
aid = 'fb294b68b1514ec12aa50fe0d77accf9'
gid = '1e6028dab84d4a17a1b3fb28ad51df5d'

H = {
    'Authorization': 'Bearer ' + token,
    'client-token': ctok,
    'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': '1.3.1.234.g59d6bf59',
}

paths = []
for ident, name in [(fid, 'fid'), (aid, 'aid'), (gid, 'gid')]:
    paths.append(('GET', 'https://spclient.wg.spotify.com/sneaktables/v2/hls/4/%s/audio.m3u8' % ident, name + ' audio.m3u8'))
    paths.append(('GET', 'https://spclient.wg.spotify.com/sneaktables/v2/hls/4/%s/master.m3u8' % ident, name + ' master.m3u8'))
for q in ['?product=0&partner=', '?product=0&partner=desktop', '?alt=json', '']:
    paths.append(('GET', 'https://spclient.wg.spotify.com/storage-resolve/v2/files/audio/interactive/%s%s' % (fid, q), 'v2-interactive ' + q))
    paths.append(('GET', 'https://spclient.wg.spotify.com/storage-resolve/v2/files/audio/%s%s' % (fid, q), 'v2-audio ' + q))
for method in ('GET', 'POST'):
    for ident, name in [(fid, 'fid'), (aid, 'aid')]:
        paths.append((method, 'https://spclient.wg.spotify.com/padme/v2/metadata/fileId?file_id=' + ident, 'padme-fileId ' + name))
        paths.append((method, 'https://spclient.wg.spotify.com/padme/v2/metadata/manifestId?manifest_id=' + ident, 'padme-manifestId ' + name))

for method, url, desc in paths:
    req = urllib.request.Request(url, headers=H, method=method, data=b'' if method == 'POST' else None)
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            data = r.read()
            text = data[:400]
            try:
                text = data[:400].decode()
            except Exception:
                text = data[:120].hex()
            print('[%s] %-28s HTTP %d %dB -> %s' % (method, desc, r.status, len(data), str(text).replace('\n', ' | ')[:220]))
    except urllib.error.HTTPError as e:
        body = e.read()[:150]
        try:
            body = body.decode()
        except Exception:
            pass
        print('[%s] %-28s HTTP %d -> %s' % (method, desc, e.code, str(body)[:150]))
    except Exception as e:
        print('[%s] %-28s ERR %s' % (method, desc, e))
