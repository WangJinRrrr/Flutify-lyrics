import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutify_app/services/eme/license_client.dart';
import 'package:flutify_app/services/auth/web_token_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅明确的认证失败或缺少登录态提示重新登录；403 不足以确定原因。
/// FairPlay 的证书请求也带 Web token（原生页面先取证书），Widevine 的证书只用 client-token。
void main() {
  late Directory tmp;
  late File m4a;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('eme_sign_in_test');
    m4a = File('${tmp.path}/a.m4a')..writeAsBytesSync([0]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 用 serveHlsForNative 装好反代（不依赖 WebView），返回本地 license 地址。
  Future<String> serve(
    EmePlayer p, {
    Future<Uint8List> Function(Uint8List)? license,
    Future<Uint8List> Function()? cert,
  }) async {
    final r = await p.serveHlsForNative(
      m4a: m4a,
      m3u8: '#EXTM3U',
      licensePoster: license ?? (_) async => Uint8List(0),
      certFetcher: cert ?? () async => Uint8List(0),
    );
    return r.licenseUrl;
  }

  Future<int> request(String method, String url) async {
    final c = HttpClient();
    try {
      final req = await c.openUrl(method, Uri.parse(url));
      if (method == 'POST') req.add([1, 2, 3]);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      c.close(force: true);
    }
  }

  test('FairPlay：证书阶段 Web token 被拒，提示重新 Web 登录', () async {
    final p = EmePlayer()..fairPlayModeForTesting = true;
    addTearDown(p.dispose);
    final licenseUrl = await serve(
      p,
      cert: () async => throw WebTokenHttpException(401),
    );
    expect(
      await request('GET', licenseUrl.replaceFirst('/license', '/cert')),
      500,
    );
    expect(p.lastError?.webSignInSuggested, isTrue);
  });

  test('Widevine：证书只用 client-token，401 不当作 Web 登录失效', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final licenseUrl = await serve(
      p,
      cert: () async => throw LicenseHttpException(401, isCertificate: true),
    );
    expect(
      await request('GET', licenseUrl.replaceFirst('/license', '/cert')),
      500,
    );
    expect(p.lastError, isNotNull);
    expect(p.lastError!.webSignInSuggested, isFalse);
  });

  test('从没完成 Web 登录（缺 sp_dc）也提示重新 Web 登录', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final licenseUrl = await serve(
      p,
      license: (_) async => throw WebSignInRequiredException(),
    );
    expect(await request('POST', licenseUrl), 500);
    expect(p.lastError?.webSignInSuggested, isTrue);
  });

  for (final error in <Object>[
    LicenseHttpException(403, isCertificate: false),
    WebTokenHttpException(403),
    WebTokenHttpException(429),
    StateError('media request 401403 failed'),
  ]) {
    test('$error 保留拒绝原因，不提示重新登录', () async {
      final p = EmePlayer();
      addTearDown(p.dispose);
      final url = await serve(p, license: (_) async => throw error);
      expect(await request('POST', url), 500);
      expect(p.lastError?.webSignInSuggested, isFalse);
      expect(p.lastError?.cause, same(error));
    });
  }

  test('许可证明确返回 401 时仍提示重新登录', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final url = await serve(
      p,
      license: (_) async =>
          throw LicenseHttpException(401, isCertificate: false),
    );
    expect(await request('POST', url), 500);
    expect(p.lastError?.webSignInSuggested, isTrue);
  });

  test('页面的媒体 / CDN HTTP 401 不推断为 Web 登录失效', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    p.handleJsEvent([
      jsonEncode({'type': 'error', 'msg': 'segment HTTP 401'}),
    ]);
    expect(p.lastError, isNotNull);
    expect(p.lastError?.webSignInSuggested, isFalse);
  });
}
