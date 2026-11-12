# ResolveAudioManifest JSON 变体矩阵（错误类型变化用于定位参数要求）。
import base64, json, os, sys, urllib.request

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
token = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']
did = prefs.get('flutter.sp_device_id', 'd18af24a30f57132212a3825437b86a56dab49bd')

gid = bytes.fromhex('1e6028dab84d4a17a1b3fb28ad51df5d')
uri = 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b'

url = 'https://spclient.wg.spotify.com/sequence-proxy/spotify.sequenceproxy.v1.SequenceProxyService/ResolveAudioManifest'
headers = {
    'Authorization': 'Bearer ' + token,
    'client-token': ctok,
    'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': '1.3.1.234.g59d6bf59',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
}

client = {'device': {'client_id': '65b708073fc0480ea92a077233ca87bd', 'device_id': did},
          'locale': {'language_tag': 'en'}}

variants = []
for mid_name in ('media_id', 'mediaId'):
    for mid_val, mid_desc in [
        (base64.b64encode(gid).decode(), 'gid-b64'),
        (gid.hex(), 'gid-hex'),
        (uri, 'uri'),
    ]:
        for fmt in ('', 'OGG_VORBIS_320', 'audio/ogg', '2', 'ogg_vorbis_320'):
            body = {mid_name: mid_val, 'client': client}
            if fmt:
                body['format_id' if mid_name == 'media_id' else 'formatId'] = fmt
            variants.append((mid_desc, fmt, body))

for desc, fmt, body in variants:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read().decode()
            print('%-10s fmt=%-14r -> %s' % (desc, fmt, data[:180]))
            if 'badRequest' not in data:
                open(r'D:\tmp\manifest_hit.json', 'w').write(data)
                print('  ^^ SAVED (non-badRequest)')
                sys.exit(0)
    except urllib.error.HTTPError as e:
        print('%-10s fmt=%-14r -> HTTP %d %s' % (desc, fmt, e.code, e.read()[:120]))
