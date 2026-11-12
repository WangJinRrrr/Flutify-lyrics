"""Local-only TLS ClientHello comparison; sends no account traffic."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dart', default=shutil.which('dart'), help='Path to dart executable')
parser.add_argument('--node', default=shutil.which('node'), help='Path to node executable')
parser.add_argument('--chrome', help='Path to Chrome/Chromium executable')
parser.add_argument('--out', type=Path, default=ROOT / 'tool/probe_out/tls')
args = parser.parse_args()
if not args.dart or not args.node:
    parser.error('Dart and Node are required; specify --dart and --node or add them to PATH')
OUT = args.out.resolve()
OUT.mkdir(parents=True, exist_ok=True)
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def exact(conn, size):
    data = bytearray()
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise ValueError('truncated handshake')
        data.extend(chunk)
    return bytes(data)


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, n):
        if n < 0 or self.pos + n > len(self.data):
            raise ValueError('truncated ClientHello')
        part = self.data[self.pos:self.pos+n]
        self.pos += n
        return part

    def number(self, n):
        return int.from_bytes(self.take(n), 'big')

    def vector(self, n):
        return self.take(self.number(n))


def grease(n):
    return (n & 0x0f0f) == 0x0a0a and (n >> 8) == (n & 0xff)


def u16s(data):
    return [n for (n,) in struct.iter_unpack('!H', data) if not grease(n)]


def hello_info(data):
    r = Reader(data)
    version = r.number(2)
    r.take(32)
    r.vector(1)  # session id; do not retain random values
    ciphers = u16s(r.vector(2))
    r.vector(1)
    extensions = Reader(r.vector(2))
    fields = {}
    while extensions.pos < len(extensions.data):
        kind = extensions.number(2)
        value = extensions.vector(2)
        if not grease(kind):
            fields[kind] = value
    alpn = []
    if 16 in fields:
        a = Reader(Reader(fields[16]).vector(2))
        while a.pos < len(a.data):
            alpn.append(a.vector(1).decode('ascii'))
    return {
        'legacy_version': version,
        'cipher_suites': ciphers,
        'extensions': list(fields),
        'supported_groups': u16s(Reader(fields[10]).vector(2)) if 10 in fields else [],
        'supported_versions': u16s(Reader(fields[43]).vector(1)) if 43 in fields else [],
        'signature_algorithms': u16s(Reader(fields[13]).vector(2)) if 13 in fields else [],
        'alpn': alpn,
    }


def capture(command, browser=False):
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0))
        server.listen(4)
        server.settimeout(20)
        port = server.getsockname()[1]
        proc = subprocess.Popen(command(port), stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, creationflags=NO_WINDOW,
                                start_new_session=os.name != 'nt')
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(5)
                handshake = bytearray()
                while len(handshake) < 4 or len(handshake) < 4 + int.from_bytes(handshake[1:4], 'big'):
                    hdr = exact(conn, 5)
                    if hdr[0] != 22:
                        raise ValueError('expected TLS handshake record')
                    size = int.from_bytes(hdr[3:5], 'big')
                    if size > 18432 or len(handshake) + size > 131072:
                        raise ValueError('oversized handshake')
                    handshake.extend(exact(conn, size))
                if handshake[0] != 1:
                    raise ValueError('expected ClientHello')
                return hello_info(bytes(handshake[4:4+int.from_bytes(handshake[1:4], 'big')]))
        finally:
            if os.name == 'nt' and browser and proc.poll() is None:
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                               capture_output=True, creationflags=NO_WINDOW)
            elif os.name != 'nt' and browser:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            elif proc.poll() is None:
                proc.kill()
            proc.wait(timeout=10)


dart = OUT / 'client.dart'
dart.write_text("""import 'dart:io';
Future<void> main(List<String> args) async {
  final tcp = await Socket.connect('127.0.0.1', int.parse(args.single));
  try { (await SecureSocket.secure(tcp, host: 'tls-probe.invalid')).destroy(); }
  catch (_) { tcp.destroy(); }
}
""", encoding='utf-8')
node = OUT / 'client.js'
node.write_text("""const tls = require('node:tls');
const socket = tls.connect({host:'127.0.0.1', port:Number(process.argv[2]),
  servername:'tls-probe.invalid', rejectUnauthorized:true, minVersion:'TLSv1.2'});
socket.on('error', () => socket.destroy());
""", encoding='utf-8')

results = {}
results['dart'] = capture(lambda p: [args.dart, str(dart), str(p)])
results['node'] = capture(lambda p: [args.node, str(node), str(p)])
candidates = [Path(os.environ.get(key, '')) / 'Google/Chrome/Application/chrome.exe'
              for key in ['ProgramFiles', 'ProgramFiles(x86)', 'LOCALAPPDATA']]
candidates.extend([
    Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'),
    Path(shutil.which('google-chrome') or shutil.which('chromium') or '/nonexistent'),
])
chrome = Path(args.chrome) if args.chrome else next((p for p in candidates if p.is_file()), None)
if chrome:
    profile = Path(tempfile.mkdtemp(prefix='chrome-', dir=OUT))
    try:
        results['chrome'] = capture(lambda p: [str(chrome), '--headless=new', '--no-first-run',
            '--no-default-browser-check', '--disable-background-networking', '--disable-sync',
            '--no-proxy-server', '--disable-component-update',
            '--host-resolver-rules=MAP tls-probe.invalid 127.0.0.1, MAP * ~NOTFOUND',
            '--user-data-dir=' + str(profile), f'https://tls-probe.invalid:{p}/'], browser=True)
    finally:
        resolved = profile.resolve()
        if resolved.is_relative_to(OUT.resolve()) and resolved != OUT.resolve():
            shutil.rmtree(resolved, ignore_errors=True)
else:
    results['chrome'] = {'error': 'Chrome executable not found'}
(OUT / 'result.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps(results, indent=2))
if any('error' in value for value in results.values()):
    sys.exit(1)
