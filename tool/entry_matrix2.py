# 逆向实测二轮：sneaktables HLS / manifests/v9 / padme 用 MP4 file_id 与路径参数变体。
import json, os, urllib.request, urllib.error

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
H = {
    'Authorization': 'Bearer ' + prefs['flutter.sp_access_token'],
    'client-token': prefs['flutter.sp_client_token'],
    'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': '1.3.1.234.g59d6bf59',
    'Accept': 'application/json',
}

fids = {
    'mp4_256': '8cb0e0c29cf69c73610b788e775ec1e9461dd941',
    'mp4_128': 'f6e2ff1804615a9cb45b63cbba993d3ba440eb4a',
    'ogg320': '4b47b6d3c1de4b23187c52032ad9904e6e5a9010',
}
aid = 'fb294b68b1514ec12aa50fe0d77accf9'

urls = []
for n, fid in fids.items():
    urls.append(('GET', 'https://spclient.wg.spotify.com/sneaktables/v2/hls/4/%s/audio.m3u8' % fid, 'sneak ' + n))
    urls.append(('GET', 'https://spclient.wg.spotify.com/sneaktables/v2/hls/4/%s/master.m3u8' % fid, 'sneakM ' + n))
    urls.append(('GET', 'https://spclient.wg.spotify.com/manifests/v9/json/sources/%s/options/gzip+no_h264_high+supports_drm' % fid, 'man9json ' + n))
    urls.append(('GET', 'https://spclient.wg.spotify.com/manifests/v9/audio/sources/%s/options/supports_drm' % fid, 'man9audio ' + n))
    urls.append(('GET', 'https://spclient.wg.spotify.com/padme/v2/metadata/fileId/%s' % fid, 'padme-path ' + n))
    urls.append(('POST', 'https://spclient.wg.spotify.com/padme/v2/metadata/fileId?file_id=' + fid, 'padme-q ' + n))
urls.append(('GET', 'https://spclient.wg.spotify.com/sneaktables/v2/hls/4/%s/audio.m3u8' % aid.upper(), 'sneak AID-UPPER'))
urls.append(('GET', 'https://spclient.wg.spotify.com/manifests/v9/json/sources/%s/options/gzip+no_h264_high+supports_drm' % aid, 'man9json aid'))
urls.append(('GET', 'https://spclient.wg.spotify.com/padme/v2/metadata/fileId/%s' % aid, 'padme-path aid'))

for method, url, desc in urls:
    req = urllib.request.Request(url, headers=H, method=method, data=b'' if method == 'POST' else None)
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            data = r.read()
            try:
                t = data.decode()
            except Exception:
                t = data[:120].hex()
            print('[%s] %-22s HTTP %d %dB -> %s' % (method, desc, r.status, len(data), t.replace('\n', ' | ')[:260]))
    except urllib.error.HTTPError as e:
        body = e.read()[:120]
        try:
            body = body.decode()
        except Exception:
            pass
        print('[%s] %-22s HTTP %d -> %s' % (method, desc, e.code, str(body)[:120]))
    except Exception as e:
        print('[%s] %-22s ERR %s' % (method, desc, e))
