import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lyrics_disk_cache.dart';
import 'package:flutify_app/services/lyrics/netease_client.dart';
import 'package:flutify_app/services/lyrics/netease_translation_source.dart';
import 'package:flutify_app/services/network/network_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 网易云接口客户端：不伪造来源 IP、风控冷却、瞬时故障重试。网络与时钟全部用替身。
void main() {
  late DateTime now;
  late List<http.Request> requests;
  late List<Duration> sleeps;

  setUp(() {
    now = DateTime(2026, 10, 1, 20);
    requests = [];
    sleeps = [];
  });

  /// 记下每个请求与每次退避等待；时钟停在 [now]，由测试手动拨动。
  NeteaseClient client(http.Response Function(http.Request) handler) =>
      NeteaseClient(
        MockClient((req) async {
          requests.add(req);
          return handler(req);
        }),
        sleep: (d) async => sleeps.add(d),
        now: () => now,
      );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response ok(http.Request req) => req.url.path.contains('search')
      ? json({
          'code': 200,
          'result': {
            'songs': [
              {
                'id': 7,
                'name': 'Mystery of Love',
                'artists': [
                  {'name': 'Sufjan Stevens'},
                ],
                'duration': 248920,
              },
            ],
          },
        })
      : json({
          'code': 200,
          'lrc': {'lyric': '[00:18.15]Oh, to see without my eyes'},
          'tlyric': {'lyric': '[00:18.15]闭上双眼 仍能清晰回忆起彼时'},
        });

  group('NeteaseClient', () {
    test('不伪造来源 IP，且请求的主机走 NetworkProxy 的直连规则', () async {
      final c = client(ok);
      expect((await c.search('Mystery of Love')).value?.single.id, 7);
      expect((await c.lyric(7)).value?.tlyric, contains('闭上双眼'));
      expect(requests, hasLength(2));
      for (final req in requests) {
        final names = req.headers.keys.map((k) => k.toLowerCase());
        expect(names, isNot(contains('x-real-ip')), reason: '${req.url}');
        expect(names, isNot(contains('x-forwarded-for')), reason: '${req.url}');
        // 不再伪造来源 IP 的前提：网易云不经用户为 Spotify 开的海外代理
        expect(
          NetworkProxy.isAlwaysDirect(req.url.host),
          isTrue,
          reason: '${req.url}',
        );
      }
    });

    test('风控（业务码 -460）：只请求一次不重试，记为网络错误；冷却期内不再发请求', () async {
      final c = client((_) => json({'code': -460, 'message': 'Cheating'}));
      final res = await c.search('Mystery of Love');
      expect(res.value, isNull);
      expect(res.networkError, isTrue, reason: '不能当成「没搜到」缓存下来');
      expect(requests, hasLength(1), reason: '风控按出口 IP 判定，马上重试照样被拒');
      expect(sleeps, isEmpty);

      now = now.add(NeteaseClient.cooldown - const Duration(seconds: 1));
      final searched = await c.search('Mystery of Love');
      final lyric = await c.lyric(7);
      expect(searched.networkError, isTrue);
      expect(lyric.value, isNull);
      expect(lyric.networkError, isTrue);
      expect(requests, hasLength(1), reason: '冷却期内 search / lyric 都直接返回');
    });

    test('冷却期过后恢复请求', () async {
      var blocked = true;
      final c = client((req) => blocked ? json({'code': -462}) : ok(req));
      expect((await c.lyric(7)).networkError, isTrue);
      blocked = false;

      now = now.add(NeteaseClient.cooldown);
      final res = await c.lyric(7);
      expect(res.networkError, isFalse);
      expect(res.value?.tlyric, contains('闭上双眼'));
      expect(requests, hasLength(2));
    });

    test('HTTP 403 与业务码风控同样处理：不重试、记为网络错误（不当「没有」）、进入冷却', () async {
      final c = client((_) => http.Response('Forbidden', 403));
      final res = await c.lyric(7);
      expect(res.value, isNull);
      expect(res.networkError, isTrue);
      expect(requests, hasLength(1));
      expect(sleeps, isEmpty);

      expect((await c.search('Mystery of Love')).networkError, isTrue);
      expect(requests, hasLength(1));

      now = now.add(NeteaseClient.cooldown);
      await c.search('Mystery of Love');
      expect(requests, hasLength(2));
    });

    test('5xx 等瞬时故障照旧重试两次（退避 600 / 1200 ms），且不进入冷却', () async {
      final c = client((_) => http.Response('', 503));
      final res = await c.search('Mystery of Love');
      expect(res.networkError, isTrue);
      expect(requests, hasLength(3));
      expect(sleeps, const [
        Duration(milliseconds: 600),
        Duration(milliseconds: 1200),
      ]);

      await c.lyric(7);
      expect(requests, hasLength(6), reason: '5xx 不是风控，下一次照常请求');
    });

    test('重试后成功照常返回结果', () async {
      var calls = 0;
      final c = client(
        (req) => ++calls == 1 ? http.Response('', 502) : ok(req),
      );
      final res = await c.lyric(7);
      expect(res.networkError, isFalse);
      expect(res.value?.tlyric, contains('闭上双眼'));
      expect(requests, hasLength(2));
    });

    test('404 仍是确定的「没有」：不重试也不冷却', () async {
      final c = client((_) => http.Response('', 404));
      final res = await c.lyric(7);
      expect(res.value, isNull);
      expect(res.networkError, isFalse);
      await c.lyric(7);
      expect(requests, hasLength(2));
    });
  });

  group('NeteaseTranslationSource', () {
    const query = LyricsQuery(
      trackId: 'mol',
      title: 'Mystery of Love',
      artist: 'Sufjan Stevens',
      durationMs: 248920,
    );
    const originals = [
      LyricLine(startTimeMs: 17780, words: 'Oh, to see without my eyes'),
      LyricLine(startTimeMs: 21950, words: 'The first time that you kissed me'),
    ];

    test('搜索被风控（403）：不把「没有译文」写进缓存，也不白等按曲名重搜', () async {
      final dir = Directory.systemTemp.createTempSync('flutify_ne_client_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = LyricsDiskCache(dir);
      final src = NeteaseTranslationSource(
        client((_) => http.Response('Forbidden', 403)),
        cache: cache,
        sleep: (d) async => sleeps.add(d),
      );

      final lookup = await src.find(query, originals);
      expect(lookup.lines, isNull);
      expect(lookup.networkError, isTrue);
      expect(await cache.count(), 0, reason: '403 曾被当成「没有」落盘，这首歌从此再也查不到译文');
      expect(requests, hasLength(1));
      expect(sleeps, isEmpty);

      // 冷却期内换一首歌也不发请求
      final other = await src.find(
        const LyricsQuery(
          trackId: 'other',
          title: 'Other Song',
          artist: 'Someone',
        ),
        originals,
      );
      expect(other.networkError, isTrue);
      expect(requests, hasLength(1));
    });
  });
}
