import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本地回环服务只认自己的页面与本机播放器：外来 Host（DNS rebinding）与跨站 Origin 一律 403。
void main() {
  late Directory tmp;
  late EmePlayer player;
  late Uri license;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('eme_local_server_test');
    player = EmePlayer();
    final r = await player.serveHlsForNative(
      m4a: File('${tmp.path}/a.m4a')..writeAsBytesSync([0]),
      m3u8: '#EXTM3U',
      licensePoster: (_) async => Uint8List.fromList([7]),
      certFetcher: () async => Uint8List(0),
    );
    license = Uri.parse(r.licenseUrl);
  });

  tearDown(() async {
    await player.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<int> send(
    String method,
    String path, {
    Map<String, String>? query,
    String? host,
    String? origin,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(
        method,
        license.replace(path: path, queryParameters: query),
      );
      if (host != null) req.headers.set(HttpHeaders.hostHeader, host);
      if (origin != null) req.headers.set('origin', origin);
      if (method == 'POST') req.add([1, 2, 3]);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('本机播放器与页面的正常请求照常服务', () async {
    expect(await send('GET', '/audio.m3u8'), 200);
    expect(await send('POST', '/license'), 200);
    // 页面自己发的 POST 带本服务的 Origin
    expect(
      await send(
        'POST',
        '/license',
        origin: 'http://127.0.0.1:${license.port}',
      ),
      200,
    );
  });

  test('外来 Host（DNS rebinding）被拒', () async {
    expect(
      await send('GET', '/audio.m3u8', host: 'evil.example:${license.port}'),
      403,
    );
    expect(await send('POST', '/license', host: 'evil.example'), 403);
    // 换了端口的回环 Host 也不是本服务
    expect(await send('GET', '/audio.m3u8', host: '127.0.0.1:1'), 403);
  });

  test('跨站网页的请求（带外来 Origin）被拒', () async {
    expect(await send('POST', '/license', origin: 'https://evil.example'), 403);
    // target 指向本机不可达端口：万一放行也不会真的对外发请求
    expect(
      await send(
        'POST',
        '/provision',
        query: {'target': 'https://127.0.0.1:1/'},
        origin: 'null',
      ),
      403,
    );
  });

  test('isOwnRequest 只看 Host 与 Origin', () async {
    // 直接校验静态规则：大小写不敏感，Host 可不带端口
    final headers = await _headersOf(license, host: 'LOCALHOST');
    expect(EmePlayer.isOwnRequest(headers, license.port), isTrue);
  });

  test('provision 只接受 Google provisioning 主机', () {
    expect(
      EmePlayer.isAllowedProvisionTarget(
        'https://www.googleapis.com/certificateprovisioning/v1/devicecertificates/create',
      ),
      isTrue,
    );
    expect(
      EmePlayer.isAllowedProvisionTarget('http://www.googleapis.com/'),
      isFalse,
    );
    expect(EmePlayer.isAllowedProvisionTarget('https://127.0.0.1/'), isFalse);
    expect(
      EmePlayer.isAllowedProvisionTarget('https://evil.example/'),
      isFalse,
    );
    expect(
      EmePlayer.isAllowedProvisionTarget('https://www.googleapis.com:444/'),
      isFalse,
    );
  });
}

/// 取一份真实的请求头（HttpHeaders 不能直接构造）：起个临时服务收下请求。
Future<HttpHeaders> _headersOf(Uri base, {required String host}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final client = HttpClient();
  try {
    final received = server.first;
    final req = await client.getUrl(base.replace(port: server.port, path: '/'));
    req.headers.set(HttpHeaders.hostHeader, host);
    final pending = req.close();
    final request = await received;
    final headers = request.headers;
    request.response.close();
    await (await pending).drain<void>();
    return headers;
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}
