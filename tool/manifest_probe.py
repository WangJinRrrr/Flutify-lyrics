# 逆向实测：sequence-proxy ResolveAudioManifest（gRPC-web / protobuf）。
# Schema 全部来自 Spotify.dll 内嵌 proto 描述符（playback_platform/media/v1/requests.proto 等）。
import json, os, sys, struct, urllib.request

def varint(v):
    out = b''
    while True:
        b = v & 0x7f
        v >>= 7
        if v:
            out += bytes([b | 0x80])
        else:
            out += bytes([b])
            return out

def tag(field, wire):
    return varint((field << 3) | wire)

def fld_str(field, s):
    b = s.encode()
    return tag(field, 2) + varint(len(b)) + b

def fld_bytes(field, b):
    return tag(field, 2) + varint(len(b)) + b

def fld_msg(field, m):
    return fld_bytes(field, m)

def parse(data):
    out = []
    i = 0
    while i < len(data):
        key = 0
        sh = 0
        while True:
            b = data[i]; i += 1
            key |= (b & 0x7f) << sh
            sh += 7
            if not (b & 0x80):
                break
        field, wire = key >> 3, key & 7
        if wire == 0:
            v = 0; sh = 0
            while True:
                b = data[i]; i += 1
                v |= (b & 0x7f) << sh
                sh += 7
                if not (b & 0x80):
                    break
            out.append((field, 'varint', v))
        elif wire == 2:
            ln = 0; sh = 0
            while True:
                b = data[i]; i += 1
                ln |= (b & 0x7f) << sh
                sh += 7
                if not (b & 0x80):
                    break
            out.append((field, 'bytes', data[i:i+ln]))
            i += ln
        elif wire == 5:
            out.append((field, 'f32', data[i:i+4])); i += 4
        elif wire == 1:
            out.append((field, 'f64', data[i:i+8])); i += 8
        else:
            out.append((field, 'wire%d' % wire, None))
            break
    return out

def tree(data, depth=0):
    pad = '  ' * depth
    try:
        fields = parse(data)
    except Exception:
        return pad + '!parse\n'
    s = ''
    for f, w, v in fields:
        if w == 'bytes':
            printable = all(0x20 <= c < 0x7f for c in v) and v
            if printable:
                s += '%s#%d str(%d) %r\n' % (pad, f, len(v), v.decode())
            else:
                s += '%s#%d bytes(%d)\n' % (pad, f, len(v))
                sub = tree(v, depth + 1)
                if '!parse' not in sub:
                    s += sub
        else:
            s += '%s#%d %s=%s\n' % (pad, f, w, v)
    return s

prefs = json.load(open(os.environ['APPDATA'] + r'\com.flutify.music\flutify_app\shared_preferences.json', encoding='utf-8'))
token = prefs['flutter.sp_access_token']
ctok = prefs['flutter.sp_client_token']

# --- 请求体：AudioManifestRequest{format_id=1 string, media_id=2 bytes, client=3 Client{device=1 Device{client_id=1,device_id=2}, locale=2 Locale{language_tag=1}}} ---
gid = bytes.fromhex('1e6028dab84d4a17a1b3fb28ad51df5d')  # Blinding Lights
uri = b'spotify:track:0VjIjW4GlUZAMYd2vXMi3b'

device = fld_str(1, '65b708073fc0480ea92a077233ca87bd') + fld_str(2, prefs.get('flutter.sp_device_id', 'd18af24a30f57132212a3825437b86a56dab49bd'))
locale = fld_str(1, 'en')
client = fld_msg(1, device) + fld_msg(2, locale)

variant = sys.argv[1] if len(sys.argv) > 1 else 'gid'
media = gid if variant == 'gid' else uri
fmt = sys.argv[2] if len(sys.argv) > 2 else ''

body = (fld_str(1, fmt) if fmt else b'') + fld_bytes(2, media) + fld_msg(3, client)

url = 'https://spclient.wg.spotify.com/sequence-proxy/spotify.sequenceproxy.v1.SequenceProxyService/ResolveAudioManifest'
headers = {
    'Authorization': 'Bearer ' + token,
    'client-token': ctok,
    'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': '1.3.1.234.g59d6bf59',
    'Accept': 'application/protobuf',
    'Content-Type': 'application/protobuf',
}

for framing, payload in [('plain', body), ('grpc-web', b'\x00' + struct.pack('>I', len(body)) + body)]:
    req = urllib.request.Request(url, data=payload, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read()
            print('==', variant, 'fmt=%r' % fmt, framing, 'HTTP', r.status, len(data), 'B')
            if framing == 'grpc-web' and len(data) > 5:
                data = data[5:]
            print(tree(data)[:3000])
    except urllib.error.HTTPError as e:
        print('==', variant, 'fmt=%r' % fmt, framing, 'HTTP', e.code, e.read()[:300])
    except Exception as e:
        print('==', variant, 'fmt=%r' % fmt, framing, 'ERR', e)
