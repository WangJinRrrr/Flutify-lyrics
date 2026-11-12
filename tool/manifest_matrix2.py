# ResolveAudioManifest 参数定位第二轮：media_id 语义探测。
import base64, json, os, sys, urllib.request

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
token = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']
did = prefs.get('flutter.sp_device_id', 'd18af24a30f57132212a3825437b86a56dab49bd')

gid = bytes.fromhex('1e6028dab84d4a17a1b3fb28ad51df5d')
file_id = bytes.fromhex('4b47b6d3c1de4b23187c52032ad9904e6e5a9010')
uri = b'spotify:track:0VjIjW4GlUZAMYd2vXMi3b'

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

mids = [
    ('uri-b64', base64.b64encode(uri).decode()),
    ('fileid-b64', base64.b64encode(file_id).decode()),
    ('gid-b64-pad', base64.b64encode(gid + b'\x00').decode()),
    ('gid-b64-url', base64.urlsafe_b64encode(gid).decode()),
    ('gid-hexpref', '0x' + gid.hex()),
    ('base62', '0VjIjW4GlUZAMYd2vXMi3b'),
]
fmts = ['', 'OGG_VORBIS_320', 'ogg_vorbis_320', '2', '12']

for desc, mid in mids:
    for fmt in fmts:
        body = {'media_id': mid, 'client': client}
        if fmt:
            body['format_id'] = fmt
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method='POST')
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                data = r.read().decode()
                mark = '<<' if 'badRequest' not in data else ''
                print('%-12s fmt=%-14r -> %s %s' % (desc, fmt, data[:150], mark))
                if 'badRequest' not in data:
                    open(r'D:\tmp\manifest_hit.json', 'w').write(data)
        except urllib.error.HTTPError as e:
            print('%-12s fmt=%-14r -> HTTP %d %s' % (desc, fmt, e.code, e.read()[:100]))
