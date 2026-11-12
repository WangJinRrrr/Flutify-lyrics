import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart' show PlayerState;
import 'package:flutify_app/services/eme/eme_audio_engine.dart';
import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// 快速切歌时上一首的残留错误（反代晚到失败 / 页面旧实例事件）不得污染当前曲目。
void main() {
  late Directory tmp;
  late File m4a;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('eme_gen_test');
    m4a = File('${tmp.path}/a.m4a')..writeAsBytesSync([0]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String ev(Map<String, dynamic> m) => jsonEncode(m);

  /// 用 serveHlsForNative 开新代次（不依赖 WebView）。
  Future<({String licenseUrl})> serve(
    EmePlayer p,
    Future<Uint8List> Function(Uint8List) poster,
  ) async {
    final r = await p.serveHlsForNative(
      m4a: m4a,
      m3u8: '#EXTM3U',
      licensePoster: poster,
      certFetcher: () async => Uint8List(0),
    );
    return (licenseUrl: r.licenseUrl);
  }

  Future<int> post(String url) async {
    final c = HttpClient();
    try {
      final req = await c.postUrl(Uri.parse(url));
      req.add([1, 2, 3]);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      c.close(force: true);
    }
  }

  test('上一首在途的 license 反代晚到失败：只回 500，不记 lastError、不发 error 状态', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final states = <EmePlayerState>[];
    p.stateStream.listen(states.add);

    final pending = Completer<Uint8List>();
    final first = await serve(p, (_) => pending.future);
    final status = post(first.licenseUrl);
    // 等请求进到反代（入口已记下旧代次）
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await serve(p, (_) async => Uint8List(0)); // 切歌：新代次
    pending.completeError(StateError('HTTP 403'));
    expect(await status, 500);
    await Future<void>.delayed(Duration.zero);
    expect(p.lastError, isNull);
    expect(states, isEmpty);
  });

  test('当前代次的 license 反代失败照常上报', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final states = <EmePlayerState>[];
    p.stateStream.listen(states.add);

    final cur = await serve(p, (_) async => throw StateError('HTTP 403'));
    expect(await post(cur.licenseUrl), 500);
    await Future<void>.delayed(Duration.zero);
    expect(p.lastError, isNotNull);
    expect(p.lastError!.webSignInSuggested, isFalse);
    expect(states, [EmePlayerState.error]);
  });

  test('页面事件：代次不符的 error 忽略，当前代次 / 无代次的照常处理', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final states = <EmePlayerState>[];
    p.stateStream.listen(states.add);
    await serve(p, (_) async => Uint8List(0));
    final gen = p.playGeneration;

    p.handleJsEvent([
      ev({'type': 'error', 'msg': 'old', 'gen': gen - 1}),
    ]);
    p.handleJsEvent([
      ev({'type': 'playing', 'gen': gen - 1}),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(p.lastError, isNull);
    expect(states, isEmpty);

    p.handleJsEvent([
      ev({'type': 'error', 'msg': 'cur', 'gen': gen}),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(p.lastError?.message, contains('cur'));
    expect(states, [EmePlayerState.error]);
  });

  test('EmeAudioEngine：error 投递前已换歌（lastError 已清空）则不上报', () async {
    final p = EmePlayer();
    final engine = EmeAudioEngine(
      player: p,
      licensePoster: (_) async => Uint8List(0),
      certFetcher: () async => Uint8List(0),
    );
    addTearDown(engine.dispose);
    final errors = <Object>[];
    final states = <PlayerState>[];
    engine.emeErrors.listen(errors.add);
    engine.playerStateStream.listen(states.add);

    await serve(p, (_) async => Uint8List(0));
    p.handleJsEvent([
      ev({'type': 'error', 'msg': 'x', 'gen': p.playGeneration}),
    ]);
    // 状态事件异步投递：送达前就开了下一首
    await serve(p, (_) async => Uint8List(0));
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    expect(states, isEmpty);
  });

  group('页面脚本', () {
    // 页面入口函数体：从 `window.<name> =` 到下一个 window.* 入口或启动探测段为止
    String pageFn(String name) {
      final start = emePageHtml.indexOf('window.$name = ');
      expect(start, greaterThanOrEqualTo(0), reason: '页面缺 $name');
      final ends = [
        emePageHtml.indexOf('\nwindow.', start + 1),
        emePageHtml.indexOf('// 启动时探测一次', start),
      ].where((i) => i >= 0);
      return emePageHtml.substring(start, ends.reduce((a, b) => a < b ? a : b));
    }

    test('emePlayHls 接收代次，所有事件经 gsend 携带代次', () {
      expect(
        emePageHtml,
        contains(
          'window.emePlayHls = (fairPlay, gen, autoplay = true, revision = 0, position = 0) =>',
        ),
      );
      final body = pageFn('emePlayHls');
      // 除 gsend 自身定义外，函数体内不得再有裸 send(
      final bare = RegExp(r'(?<![g\w])send\(').allMatches(body).length;
      expect(bare, 1, reason: '仅 gsend 定义里调用一次 send');
      expect(body, contains("gsend('error'"));
    });

    test('emePlayNativeFps（macOS 原生 HLS + 旧版 EME）同样接收代次、事件经 gsend', () {
      expect(
        emePageHtml,
        contains(
          'window.emePlayNativeFps = (gen, fileIdHex, autoplay = true, revision = 0, position = 0) =>',
        ),
      );
      final body = pageFn('emePlayNativeFps');
      final bare = RegExp(r'(?<![g\w])send\(').allMatches(body).length;
      expect(bare, 1, reason: '仅 gsend 定义里调用一次 send');
      expect(body, contains("gsend('error'"));
      expect(body, contains("'com.apple.fps.1_0'"));
      expect(body, contains("el.src = '/audio.m3u8'"));
    });

    test('stall 监听模块级保存、换歌先摘除，stall 信号带代次并比对', () {
      expect(emePageHtml, contains('let stallListener = null;'));
      expect(
        emePageHtml,
        contains("window.removeEventListener('emeStall', stallListener)"),
      );
      expect(emePageHtml, contains('detail: {stage: tag, gen}'));
      expect(
        emePageHtml,
        contains(
          'if (ev.detail.gen !== myGen || curGen !== myGen || intentGen !== myGen) return;',
        ),
      );
    });
  });
}
