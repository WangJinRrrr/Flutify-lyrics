# ResolveAudioManifest 第三轮：media_id = AudioFilesExtensionResponse 里的 audio_id。
import base64, json, os, sys, urllib.request

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
token = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']
did = prefs.get('flutter.sp_device_id', 'd18af24a30f57132212a3825437b86a56dab49bd')

audio_id = bytes.fromhex('fb294b68b1514ec12aa50fe0d77accf9')

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

variants = [
    ('aid-b64', base64.b64encode(audio_id).decode()),
    ('aid-hex', audio_id.hex()),
]
fmts = ['', 'OGG_VORBIS_320', '2', '0', 'aac_24', 'AAC_24', 'flac', 'FLAC_FLAC', 'ogg', 'audio/ogg', '1']

for desc, mid in variants:
    for fmt in fmts:
        body = {'media_id': mid, 'client': client}
        if fmt:
            body['format_id'] = fmt
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method='POST')
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                data = r.read().decode()
                mark = '<<' if 'badRequest' not in data else ''
                print('%-8s fmt=%-12r -> %s %s' % (desc, fmt, data[:160], mark))
                if 'badRequest' not in data:
                    open(r'D:\tmp\manifest_hit.json', 'w').write(data)
        except urllib.error.HTTPError as e:
            print('%-8s fmt=%-12r -> HTTP %d %s' % (desc, fmt, e.code, e.read()[:100]))
