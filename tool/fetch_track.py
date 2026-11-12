# 逆向全链路一键下载：track URI → track-playback/v1/media → sneaktables/hls/3 → fMP4 拼装。
# 用法：python tool/fetch_track.py <trackId|spotify:track:...> [out.m4a]
import json, os, re, sys, urllib.request

def get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()

def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else '118Y23GcMNPokkU6fXBU79'
    out_path = sys.argv[2] if len(sys.argv) > 2 else r'D:\tmp\track.m4a'
    tid = arg.rstrip('/').split('/')[-1].split('?')[0]
    if tid.startswith('spotify:'):
        tid = tid.split(':')[-1]
    uri = 'spotify:track:' + tid

    prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
    H = {
        'Authorization': 'Bearer ' + prefs['flutter.sp_access_token'],
        'client-token': prefs['flutter.sp_client_token'],
        'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
        'app-platform': 'Win32_x86_64',
        'spotify-app-version': '1.3.1.234.g59d6bf59',
        'Accept': 'application/json',
    }

    # 1) 文件清单
    media = json.loads(get(
        'https://spclient.wg.spotify.com/track-playback/v1/media/%s?manifestFileFormat=file_ids_mp4&manifestFileFormat=file_ids_mp4_cbcs&manifestFileFormat=file_urls_mp3' % uri, H))
    item = media['media'][uri]['item']
    name = item['metadata']['name']
    dur = item['metadata']['duration']
    files = []
    for k, v in (item.get('manifest') or {}).items():
        for f in v or []:
            files.append((k, f.get('format'), f.get('bitrate'), f.get('file_id'), f.get('file_url')))
    print('♪ %s  duration=%.1fs' % (name, dur / 1000))
    for k, fmt, br, fid, url in files:
        print('  [%s] fmt=%s br=%s fid=%s url=%s' % (k, fmt, br, (fid or '')[:16], bool(url)))

    # 2) 选最高码率的 MP4 文件（格式 11=MP4_256, 10=MP4_128），无 DRM 直链优先
    direct = [f for f in files if f[4]]
    if direct:
        print('直链文件（免密钥）:', direct[0][4][:80])
        data = get(direct[0][4], H)
        open(out_path, 'wb').write(data)
        print('saved ->', out_path, len(data), 'B')
        return

    cands = sorted([f for f in files if f[3] and f[0] in ('file_ids_mp4', 'file_ids_mp4_cbcs', 'file_ids_mp4_dual')],
                   key=lambda f: f[2] or 0, reverse=True)
    if not cands:
        print('!! 无可用 MP4 文件'); return
    fid = cands[0][3]
    print('chosen: %s br=%s fid=%s' % (cands[0][0], cands[0][2], fid))

    # 3) HLS 清单（policy 3 = METHOD=NONE）
    m3u8 = get('https://spclient.wg.spotify.com/sneaktables/v2/hls/3/%s/audio.m3u8' % fid,
               {**H, 'Accept': 'application/vnd.apple.mpegurl'}).decode()
    if 'METHOD=NONE' not in m3u8:
        print('!! 清单带加密，需密钥流程'); print(m3u8[:400]); return

    # 4) 按 byterange 下载拼装
    entries = []
    pending = None
    for line in m3u8.splitlines():
        line = line.strip()
        m = re.search(r'#EXT-X-MAP:URI="([^"]+)".*?BYTERANGE="(\d+)@(\d+)"', line)
        if m:
            entries.append((m.group(1), int(m.group(3)), int(m.group(2))))
            continue
        m = re.search(r'#EXT-X-BYTERANGE:(\d+)@(\d+)', line)
        if m:
            pending = (int(m.group(1)), int(m.group(2)))
            continue
        if line.startswith('http') and pending:
            entries.append((line, pending[1], pending[0]))
            pending = None
    total = sum(e[2] for e in entries)
    print('%d byte-ranges, total %.2f MB' % (len(entries), total / 1e6))
    with open(out_path, 'wb') as out:
        for n, (url, off, ln) in enumerate(entries):
            req = urllib.request.Request(url, headers={'Range': 'bytes=%d-%d' % (off, off + ln - 1)})
            with urllib.request.urlopen(req, timeout=30) as r:
                out.write(r.read())
    print('saved ->', out_path, os.path.getsize(out_path), 'B')

main()
