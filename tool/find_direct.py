# 找出 file_urls_mp3/file_urls_external 可用的曲目（直链免密钥）。
# 并对比 desktop UA / web UA 返回差异。
import json, os, sys, urllib.request, urllib.error

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
tok = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']

UAS = {
    'desktop': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
    'web': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
}

tracks = sys.argv[1:] or [
    '118Y23GcMNPokkU6fXBU79',  # My Way
    '0VjIjW4GlUZAMYd2vXMi3b',  # Blinding Lights
    '2plbrEY59IikOBgBGLjaoe',  # September (老歌)
    '4PTG3Z6ehGkBFwjybzWkR8',  # Never Gonna Give You Up
    '6habFhsOp2NvshLv26Dqz0',  # Stayin' Alive
]

for tid in tracks:
    uri = 'spotify:track:' + tid
    for ua_name, ua in UAS.items():
        H = {
            'Authorization': 'Bearer ' + tok,
            'client-token': ctok,
            'User-Agent': ua,
            'Accept': 'application/json',
        }
        url = ('https://spclient.wg.spotify.com/track-playback/v1/media/%s'
               '?manifestFileFormat=file_urls_mp3&manifestFileFormat=file_urls_external&manifestFileFormat=file_ids_mp3' % uri)
        req = urllib.request.Request(url, headers=H)
        try:
            with urllib.request.urlopen(req, timeout=12) as r:
                d = json.loads(r.read())
                item = d['media'][uri]['item']
                man = item.get('manifest') or {}
                name = item['metadata']['name']
                for k, v in man.items():
                    print('%-22s %-8s %-24s %s' % (name[:20], ua_name, k, json.dumps(v)[:220]))
                if not man:
                    print('%-22s %-8s (empty)' % (name[:20], ua_name))
        except urllib.error.HTTPError as e:
            print('%-22s %-8s HTTP %d' % (tid, ua_name, e.code))
        except Exception as e:
            print('%-22s %-8s ERR %s' % (tid, ua_name, e))
