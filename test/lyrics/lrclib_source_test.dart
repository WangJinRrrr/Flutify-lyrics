import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lrclib_client.dart';
import 'package:flutify_app/services/lyrics/lrclib_lyrics_source.dart';
import 'package:flutify_app/services/lyrics/lyrics_disk_cache.dart';
import 'package:flutify_app/services/lyrics/lyrics_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// LRCLIB 客户端（重试 / 404）、查询来源（磁盘缓存）、官方 + 补全合并器。网络全部用内存替身。
void main() {
  Future<void> noSleep(Duration _) async {}
  const synced = '[00:01.00]line one\n[00:02.00]line two';
  const query = LyricsQuery(
    trackId: 'abc',
    title: 'Song',
    artist: 'Singer, Guest',
    durationMs: 180000,
  );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  group('LrclibClient', () {
    test('404 视为没有，不算网络错误', () async {
      var calls = 0;
      final client = LrclibClient(
        MockClient((_) async {
          calls++;
          return http.Response('', 404);
        }),
        sleep: noSleep,
      );
      final res = await client.get(track: 'Song', artist: 'Singer');
      expect(res.candidates, isEmpty);
      expect(res.networkError, isFalse);
      expect(calls, 1);
    });

    test('5xx 重试两次后记为网络错误', () async {
      var calls = 0;
      final client = LrclibClient(
        MockClient((_) async {
          calls++;
          return http.Response('', 503);
        }),
        sleep: noSleep,
      );
      final res = await client.search(track: 'Song');
      expect(res.networkError, isTrue);
      expect(calls, 3);
    });

    test('429 不立即重试，冷却结束后恢复查询', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 10, 4);
      final client = LrclibClient(
        MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('', 429)
              : json([
                  {'trackName': 'Song', 'syncedLyrics': synced},
                  {'trackName': 'Song', 'plainLyrics': 'no timing'},
                ]);
        }),
        sleep: noSleep,
        now: () => now,
      );
      expect((await client.search(track: 'Song')).networkError, isTrue);
      expect((await client.get(track: 'Other', artist: 'Singer')).networkError, isTrue);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 1));
      final res = await client.search(track: 'Song');
      expect(res.candidates, hasLength(1), reason: '没有同步歌词的记录被丢弃');
      expect(res.networkError, isFalse);
    });

    test('只传非空参数', () async {
      late Uri uri;
      final client = LrclibClient(
        MockClient((req) async {
          uri = req.url;
          return json(<Object>[]);
        }),
        sleep: noSleep,
      );
      await client.search(track: 'Song', artist: '');
      expect(uri.queryParameters, {'track_name': 'Song'});
    });
  });

  group('LrclibLyricsSource', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('flutify_lrc_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('命中后写入磁盘缓存，下次不再请求', () async {
      final paths = <String>[];
      final client = LrclibClient(
        MockClient((req) async {
          paths.add('${req.url.path}?${req.url.query}');
          return req.url.path.endsWith('/get')
              ? json({'trackName': 'Song', 'syncedLyrics': synced})
              : json([]);
        }),
        sleep: noSleep,
      );
      final cache = LyricsDiskCache(dir);
      final source = LrclibLyricsSource(client, cache: cache, sleep: noSleep);

      final first = await source.find(query);
      expect(first.lyrics?.provider, LyricsProvider.lrclib);
      expect(first.lyrics?.lines.map((l) => l.words), ['line one', 'line two']);
      expect(
        paths.any(
          (p) =>
              p.contains('artist_name=Singer') &&
              !p.contains('Guest') &&
              p.contains('/search'),
        ),
        isTrue,
        reason: 'search 只带第一位艺人',
      );
      final count = paths.length;

      final second = await source.find(query);
      expect(second.lyrics?.lines, hasLength(2));
      expect(paths, hasLength(count));

      await source.forget(query);
      await source.find(query);
      expect(paths.length, greaterThan(count));
    });

    test('全部失败时带出网络错误标记', () async {
      final client = LrclibClient(
        MockClient((_) async => http.Response('', 500)),
        sleep: noSleep,
      );
      final res = await LrclibLyricsSource(client, sleep: noSleep).find(query);
      expect(res.lyrics, isNull);
      expect(res.networkError, isTrue);
    });

    test('双语对照拆出译文；磁盘缓存命中路径同样带译文', () async {
      const bilingual =
          '[00:01.00]line one\n[00:01.00]第一句\n[00:02.00]line two\n[00:02.00]第二句\n'
          '[00:03.00]line three\n[00:03.00]第三句';
      final client = LrclibClient(
        MockClient(
          (req) async => req.url.path.endsWith('/get')
              ? json({'trackName': 'Song', 'syncedLyrics': bilingual})
              : json([]),
        ),
        sleep: noSleep,
      );
      final source = LrclibLyricsSource(
        client,
        cache: LyricsDiskCache(dir),
        sleep: noSleep,
      );

      final first = await source.find(query);
      expect(first.lyrics?.lines.map((l) => l.words), [
        'line one',
        'line two',
        'line three',
      ]);
      expect(first.lyrics?.lines.map((l) => l.translation), [
        '第一句',
        '第二句',
        '第三句',
      ]);
      expect(first.lyrics?.language, 'und', reason: '拉丁文字不能直接认定为英语');

      final second = await source.find(query);
      expect(second.lyrics?.lines.map((l) => l.translation), [
        '第一句',
        '第二句',
        '第三句',
      ]);
    });
  });

  group('LyricsResolver', () {
    LrclibLyricsSource source(http.Response Function(http.Request) handler) =>
        LrclibLyricsSource(
          LrclibClient(MockClient((req) async => handler(req)), sleep: noSleep),
          sleep: noSleep,
        );

    final found = source(
      (req) => req.url.path.endsWith('/get')
          ? json({'trackName': 'Song', 'syncedLyrics': synced})
          : json([]),
    );

    test('官方只有未同步歌词时用 LRCLIB 升级', () async {
      final resolver = LyricsResolver(
        (_) async => const SpotifyLyrics(
          syncType: 'UNSYNCED',
          lines: [LyricLine(startTimeMs: 0, words: 'x')],
        ),
        fallback: found,
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.provider, LyricsProvider.lrclib);
      expect(res.cacheable, isTrue);
    });

    test('LRCLIB 网络失败时保留官方结果但不缓存', () async {
      final resolver = LyricsResolver(
        (_) async => const SpotifyLyrics(),
        fallback: source((_) => http.Response('', 503)),
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.lines, isEmpty);
      expect(res.cacheable, isFalse);
    });

    test('官方请求出错且 LRCLIB 找到时用 LRCLIB', () async {
      final resolver = LyricsResolver(
        (_) async => throw const HttpException('boom'),
        fallback: found,
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.provider, LyricsProvider.lrclib);
    });

    test('官方请求出错且 LRCLIB 也没有时抛出原错误', () async {
      final resolver = LyricsResolver(
        (_) async => throw const HttpException('boom'),
        fallback: source((_) => http.Response('', 404)),
      );
      expect(resolver.resolve(query), throwsA(isA<HttpException>()));
    });
  });
}
