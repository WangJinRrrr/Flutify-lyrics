# track-playback/v1/media 参数矩阵：manifestFileFormat 取值探测。
import json, os, sys, urllib.request, urllib.error, urllib.parse

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

uri_raw = 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b'
id_variants = [
    ('uri-raw', uri_raw),
    ('uri-enc', urllib.parse.quote(uri_raw, safe='')),
    ('base62', '0VjIjW4GlUZAMYd2vXMi3b'),
    ('gid', '1e6028dab84d4a17a1b3fb28ad51df5d'),
]
fmt_variants = ['3', 'OGG_VORBIS_320', 'FORMAT_OGG_VORBIS_320', 'ogg', 'audio/ogg', 'MANIFEST_OGG', '2', '1', '0']

for idesc, ident in id_variants:
    for fmt in fmt_variants:
        url = 'https://spclient.wg.spotify.com/track-playback/v1/media/%s?manifestFileFormat=%s' % (ident, fmt)
        req = urllib.request.Request(url, headers=H)
        try:
            with urllib.request.urlopen(req, timeout=12) as r:
                data = r.read()
                print('%-8s %-22r HTTP %d %dB -> %s' % (idesc, fmt, r.status, len(data), data[:200]))
                open(r'D:\tmp\media_hit.json', 'wb').write(data)
        except urllib.error.HTTPError as e:
            body = e.read()[:90]
            try:
                body = body.decode()
            except Exception:
                pass
            print('%-8s %-22r HTTP %d -> %s' % (idesc, fmt, e.code, str(body)[:90]))
        except Exception as e:
            print('%-8s %-22r ERR %s' % (idesc, fmt, e))
