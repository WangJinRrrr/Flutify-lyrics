# 检查各 manifestFileFormat 对给定曲目的可用性。
import json, os, sys, urllib.request, urllib.error

tid = sys.argv[1] if len(sys.argv) > 1 else '118Y23GcMNPokkU6fXBU79'
uri = 'spotify:track:' + tid

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
H = {
    'Authorization': 'Bearer ' + prefs['flutter.sp_access_token'],
    'client-token': prefs['flutter.sp_client_token'],
    'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
    'app-platform': 'Win32_x86_64',
    'Accept': 'application/json',
}

formats = ['file_urls_mp3', 'file_urls_external', 'file_ids_mp3', 'manifest_urls_audio_ad',
           'file_ids_mp4flac', 'manifest_ids_video', 'file_ids_mp4', 'file_ids_mp4_cbcs']
for fmt in formats:
    url = 'https://spclient.wg.spotify.com/track-playback/v1/media/%s?manifestFileFormat=%s' % (uri, fmt)
    req = urllib.request.Request(url, headers=H)
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            d = json.loads(r.read())
            item = d['media'][uri]['item']
            man = item.get('manifest') or {}
            keys = list(man.keys())
            out = ''
            for k, v in man.items():
                out += '%s=%s ' % (k, json.dumps(v)[:200])
            print('%-24s HTTP %d keys=%s %s' % (fmt, r.status, keys, out[:260]))
    except urllib.error.HTTPError as e:
        print('%-24s HTTP %d %s' % (fmt, e.code, e.read()[:100]))
    except Exception as e:
        print('%-24s ERR %s' % (fmt, e))
