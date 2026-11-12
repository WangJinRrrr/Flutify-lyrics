import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lyrics_disk_cache.dart';
import 'package:flutify_app/services/lyrics/lyrics_resolver.dart';
import 'package:flutify_app/services/lyrics/lyrics_translation.dart';
import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/services/lyrics/netease_client.dart';
import 'package:flutify_app/services/lyrics/netease_translation_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 网易云译文源：搜歌、挑歌、对齐到现有歌词、磁盘缓存、与 LyricsResolver 的集成。网络全部用内存替身。
void main() {
  Future<void> noSleep(Duration _) async {}

  // 网易云自己的原文时间轴（与我们的 Spotify 时间轴刻意不同，验证文本锚定）
  const refLrc =
      '[00:00.000] 作词 : Sufjan Stevens\n'
      '[00:18.150]Oh, to see without my eyes\n'
      '[00:21.960]The first time that you kissed me\n'
      '[00:26.660]Boundless by the time I cried\n'
      '[00:30.820]I built your walls around me';
  const tlyric =
      '[by:符卡]\n'
      '[00:18.150]闭上双眼 仍能清晰回忆起彼时\n'
      '[00:21.960]最初 那吻印下的时刻\n'
      '[00:26.660]如今我的泪 却旖旎不至尽头\n'
      '[00:30.820]我用我的名字筑起高墙';

  final originals = [
    const LyricLine(startTimeMs: 17780, words: 'Oh, to see without my eyes'),
    const LyricLine(
      startTimeMs: 21950,
      words: 'The first time that you kissed me',
    ),
    const LyricLine(startTimeMs: 26750, words: 'Boundless by the time I cried'),
    const LyricLine(startTimeMs: 30820, words: 'I built your walls around me'),
  ];

  const query = LyricsQuery(
    trackId: 'mol',
    title: 'Mystery of Love',
    artist: 'Sufjan Stevens',
    durationMs: 248920,
  );

  http.Response searchJson(List<Map<String, Object>> songs) => http.Response(
    jsonEncode({
      'result': {'songs': songs},
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object> song({
    int id = 516358164,
    String name = 'Mystery of Love',
    String artist = 'Sufjan Stevens',
    int duration = 248920,
  }) => {
    'id': id,
    'name': name,
    'artists': [
      {'name': artist},
    ],
    'album': {'name': 'Call Me By Your Name'},
    'duration': duration,
  };

  http.Response lyricJson({String lrc = refLrc, String t = tlyric}) =>
      http.Response(
        jsonEncode({
          'code': 200,
          'lrc': {'lyric': lrc},
          'tlyric': {'lyric': t},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  NeteaseClient mockClient(
    http.Response Function(http.Request) handler, {
    List<String>? log,
  }) => NeteaseClient(
    MockClient((req) async {
      log?.add('${req.method} ${req.url.path}');
      return handler(req);
    }),
    sleep: noSleep,
  );

  NeteaseTranslationSource source(
    http.Response Function(http.Request) handler, {
    LyricsDiskCache? cache,
    List<String>? log,
  }) => NeteaseTranslationSource(
    mockClient(handler, log: log),
    cache: cache,
    sleep: noSleep,
  );

  http.Response mysteryOfLove(http.Request req) =>
      req.url.path.contains('search') ? searchJson([song()]) : lyricJson();

  group('NeteaseTranslationSource', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('flutify_ne_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Suzume source title with an unbracketed featured artist matches', () {
      const q = LyricsQuery(
        trackId: 'suzume',
        title: 'すずめ',
        artist: 'RADWIMPS, Toaka',
        durationMs: 236000,
      );
      expect(
        NeteaseTranslationSource.pickSong(const [
          NeteaseSong(
            id: 1,
            name: '東京上空',
            artists: 'RADWIMPS',
            durationMs: 254933,
          ),
          NeteaseSong(
            id: 1984758339,
            name: 'すずめ feat.十明',
            artists: 'RADWIMPS, 十明',
            durationMs: 236390,
          ),
          NeteaseSong(
            id: 3,
            name: 'すずめ feat.十明',
            artists: 'Cover Artist',
            durationMs: 236390,
          ),
        ], q)?.id,
        1984758339,
      );
      expect(
        NeteaseTranslationSource.baseTitle('Song featuring Artist'),
        'Song',
      );
      expect(
        NeteaseTranslationSource.baseTitle('Song features'),
        'Song features',
      );
    });

    test(
      'irrelevant search hits still allow one title-only fallback',
      () async {
        final keywords = <String>[];
        final src = source((request) {
          if (!request.url.path.contains('search')) return lyricJson();
          final keyword = Uri.splitQueryString(request.body)['s']!;
          keywords.add(keyword);
          return searchJson(
            keyword == query.title ? [song()] : [song(name: 'Other')],
          );
        });
        expect((await src.find(query, originals)).lines, isNotNull);
        expect(keywords, ['Mystery of Love Sufjan Stevens', 'Mystery of Love']);
      },
    );

    test(
      'old negative cache does not prevent corrected song matching',
      () async {
        final cache = LyricsDiskCache(dir);
        await cache.write(
          'netease|v2|mol',
          const NeteaseLyricBundle().encode(),
        );
        final log = <String>[];
        expect(
          (await source(
            mysteryOfLove,
            cache: cache,
            log: log,
          ).find(query, originals)).lines,
          isNotNull,
        );
        expect(log, hasLength(2));
      },
    );

    test('搜歌取译文并按文本锚定对齐到我们的时间轴', () async {
      final src = source(mysteryOfLove, cache: LyricsDiskCache(dir));
      final lookup = await src.find(query, originals);
      expect(lookup.networkError, isFalse);
      expect(
        lookup.lines?.map((l) => (l.startTimeMs, l.words)),
        [
          (17780, '闭上双眼 仍能清晰回忆起彼时'),
          (21950, '最初 那吻印下的时刻'),
          (26750, '如今我的泪 却旖旎不至尽头'),
          (30820, '我用我的名字筑起高墙'),
        ],
        reason: '译文要贴到我们自己的时间点，而不是网易云的时间点',
      );
    });

    test(
      'clearing the cache prevents an in-flight translation from restoring it',
      () async {
        final cache = LyricsDiskCache(dir);
        final requested = Completer<void>();
        final response = Completer<void>();
        final src = NeteaseTranslationSource(
          NeteaseClient(
            MockClient((request) async {
              if (request.url.path.contains('search'))
                return searchJson([song()]);
              requested.complete();
              await response.future;
              return lyricJson();
            }),
            sleep: noSleep,
          ),
          cache: cache,
          sleep: noSleep,
        );
        final lookup = src.find(query, originals);
        await requested.future;
        await cache.clear();
        response.complete();
        expect((await lookup).lines, isNotNull);
        expect(await cache.count(), 0);
      },
    );

    test('缓存命中后第二次不再联网（对齐在读取时重算）', () async {
      final log = <String>[];
      final cache = LyricsDiskCache(dir);
      await source(
        mysteryOfLove,
        cache: cache,
        log: log,
      ).find(query, originals);
      final calls = log.length;
      await source(
        mysteryOfLove,
        cache: cache,
        log: log,
      ).find(query, originals);
      expect(log.length, calls, reason: '第二次查询应当全部命中磁盘缓存');
    });

    test('网易云原文缺行时按时间近邻兜底（±1.5s）', () async {
      final src = source(
        (req) => req.url.path.contains('search')
            ? searchJson([song()])
            : lyricJson(lrc: '[00:18.150]Oh, to see without my eyes'), // 只剩一句原文
      );
      final lookup = await src.find(query, originals);
      // 只有第一句能文本锚定，其余按时间就近贴上：4/4 覆盖
      expect(lookup.lines, hasLength(4));
      expect(lookup.lines?.first.words, '闭上双眼 仍能清晰回忆起彼时');
    });

    test('重复的副歌：某次缺译文时其余译文贴回各自那一次，不整体前移', () {
      const ours = [
        LyricLine(startTimeMs: 10000, words: 'Intro line'),
        LyricLine(startTimeMs: 20000, words: 'Hold me close'),
        LyricLine(startTimeMs: 30000, words: 'Verse two'),
        LyricLine(startTimeMs: 40000, words: 'Hold me close'),
        LyricLine(startTimeMs: 50000, words: 'Outro'),
      ];
      const lrc =
          '[00:10.00]Intro line\n[00:20.00]Hold me close\n[00:30.00]Verse two\n'
          '[00:40.00]Hold me close\n[00:50.00]Outro';
      const tly = '[00:10.00]开场\n[00:30.00]第二段\n[00:40.00]抱紧我\n[00:50.00]尾声';
      final aligned = NeteaseTranslationSource.align(lrc, tly, ours)!;
      expect(aligned.map((l) => l.words), ['开场', '', '第二段', '抱紧我', '尾声']);
    });

    test('两条时间轴整体错开（前奏长度不同）时副歌按偏移校正后的时间贴', () {
      const ours = [
        LyricLine(startTimeMs: 20000, words: 'First verse'),
        LyricLine(startTimeMs: 30000, words: 'Hold me close'),
        LyricLine(startTimeMs: 40000, words: 'Second verse'),
        LyricLine(startTimeMs: 50000, words: 'Hold me close'),
      ];
      // 网易云的时间轴整体早 8 秒
      const lrc =
          '[00:12.00]First verse\n[00:22.00]Hold me close\n[00:32.00]Second verse\n[00:42.00]Hold me close';
      const tly = '[00:12.00]第一段\n[00:32.00]第二段\n[00:42.00]抱紧我';
      final aligned = NeteaseTranslationSource.align(lrc, tly, ours)!;
      expect(aligned.map((l) => l.words), ['第一段', '', '第二段', '抱紧我']);
    });

    test('覆盖率不足四成视为配错歌，全盘放弃', () async {
      final manyLines = [
        ...originals,
        const LyricLine(startTimeMs: 40000, words: 'some other line here'),
        const LyricLine(startTimeMs: 50000, words: 'another different line'),
        const LyricLine(startTimeMs: 60000, words: 'yet another one'),
        const LyricLine(startTimeMs: 70000, words: 'more lyrics to sing'),
        const LyricLine(startTimeMs: 80000, words: 'and even more lines'),
        const LyricLine(
          startTimeMs: 90000,
          words: 'one more line to tip the scale',
        ),
        const LyricLine(startTimeMs: 95000, words: 'the last extra line'),
      ];
      // 可贴的译文只有 4 行：4 / 11 < 0.4，低于覆盖率阈值
      final lookup = await source(mysteryOfLove).find(query, manyLines);
      expect(lookup.lines, isNull);
    });

    test('中文原文不查译文（省掉请求）', () async {
      final log = <String>[];
      final chinese = [
        const LyricLine(startTimeMs: 1000, words: '走在路上看天空'),
        const LyricLine(startTimeMs: 2000, words: '整夜不停想着你'),
      ];
      final lookup = await source(mysteryOfLove, log: log).find(query, chinese);
      expect(lookup.lines, isNull);
      expect(log, isEmpty);
    });

    test('歌手对不上的同名歌不用；时长差太多的不同版本也不用', () async {
      final wrongArtist = source(
        (req) => searchJson([song(artist: 'Someone Else')]),
      );
      expect((await wrongArtist.find(query, originals)).lines, isNull);

      final wrongVersion = source(
        (req) => searchJson([song(duration: 150000)]),
      );
      expect((await wrongVersion.find(query, originals)).lines, isNull);
    });

    test('这首歌网易云上没有译文 → 确定结果，缓存后不再请求', () async {
      final log = <String>[];
      final cache = LyricsDiskCache(dir);
      http.Response noTrans(http.Request req) => req.url.path.contains('search')
          ? searchJson([song()])
          : lyricJson(t: '');
      expect(
        (await source(
          noTrans,
          cache: cache,
          log: log,
        ).find(query, originals)).lines,
        isNull,
      );
      final calls = log.length;
      expect(
        (await source(
          noTrans,
          cache: cache,
          log: log,
        ).find(query, originals)).lines,
        isNull,
      );
      expect(log.length, calls);
    });

    test('Spotify 曲名带版本后缀（- Remastered / feat.）也能挑到网易云原曲名的歌', () {
      final songs = [
        const NeteaseSong(
          id: 1,
          name: 'Bohemian Rhapsody (Live)',
          artists: 'Queen',
          durationMs: 354000,
        ),
        const NeteaseSong(
          id: 2,
          name: 'Bohemian Rhapsody',
          artists: 'Queen',
          durationMs: 355195,
        ),
      ];
      for (final title in [
        'Bohemian Rhapsody - Remastered 2011',
        'Bohemian Rhapsody (feat. Someone)',
        'Bohemian Rhapsody',
      ]) {
        final q = LyricsQuery(
          trackId: 'x',
          title: title,
          artist: 'Queen',
          durationMs: 354320,
        );
        expect(
          NeteaseTranslationSource.pickSong(songs, q)?.id,
          2,
          reason: title,
        );
      }
    });

    test('去版本后缀只认版本标记：伴奏 / Cover 等不是同一份歌词，不当同名', () {
      expect(
        NeteaseTranslationSource.baseTitle('Lemon - 2011 Remaster'),
        'Lemon',
      );
      expect(NeteaseTranslationSource.baseTitle('Lemon (Radio Edit)'), 'Lemon');
      expect(NeteaseTranslationSource.baseTitle('Lemon（伴奏）'), 'Lemon（伴奏）');
      expect(
        NeteaseTranslationSource.baseTitle('Lemon（Cover 米津玄师）'),
        'Lemon（Cover 米津玄师）',
      );
      expect(
        NeteaseTranslationSource.baseTitle('Rock - Paper - Scissors'),
        'Rock - Paper - Scissors',
      );
    });

    test('网易云上没有对得上的歌 → 确定结果，缓存后不再重搜', () async {
      final log = <String>[];
      final cache = LyricsDiskCache(dir);
      http.Response other(http.Request req) =>
          searchJson([song(name: 'Something Else')]);
      expect(
        (await source(
          other,
          cache: cache,
          log: log,
        ).find(query, originals)).lines,
        isNull,
      );
      final calls = log.length;
      expect(calls, greaterThan(0));
      expect(
        (await source(
          other,
          cache: cache,
          log: log,
        ).find(query, originals)).lines,
        isNull,
      );
      expect(log.length, calls);
    });

    test('风控（HTTP 200 + code -460）按网络错误处理，不缓存成「没有译文」', () async {
      final log = <String>[];
      final cache = LyricsDiskCache(dir);
      http.Response blocked(http.Request req) => req.url.path.contains('search')
          ? searchJson([song()])
          : http.Response(
              jsonEncode({'code': -460, 'message': 'Cheating'}),
              200,
            );
      final lookup = await source(
        blocked,
        cache: cache,
        log: log,
      ).find(query, originals);
      expect(lookup.lines, isNull);
      expect(lookup.networkError, isTrue);
      expect(await cache.count(), 0);

      // 风控解除后能正常取到（没被当成确定结果缓存）
      final ok = await source(
        mysteryOfLove,
        cache: cache,
      ).find(query, originals);
      expect(ok.lines?.first.words, '闭上双眼 仍能清晰回忆起彼时');
    });

    test('搜索被风控同样带出网络错误标记', () async {
      final lookup = await source(
        (req) => http.Response(jsonEncode({'code': -460}), 200),
      ).find(query, originals);
      expect(lookup.networkError, isTrue);
    });

    test('网络错误带出标记，且不写入缓存（下次重试）', () async {
      final log = <String>[];
      final cache = LyricsDiskCache(dir);
      final src = source(
        (req) => http.Response('', 500),
        cache: cache,
        log: log,
      );
      final lookup = await src.find(query, originals);
      expect(lookup.lines, isNull);
      expect(lookup.networkError, isTrue);
      expect(await cache.count(), 0);
    });
  });

  group('LyricsResolver 集成', () {
    SpotifyLyrics official() => SpotifyLyrics(lines: originals);

    test(
      'translation button searches source without preloading bilingual lyrics',
      () async {
        final log = <String>[];
        final resolver = LyricsResolver(
          (_) async => official(),
          translation: source(mysteryOfLove, log: log),
          translationEnabled: () => false,
          fallbackEnabled: () => false,
        );
        final lyrics = (await resolver.resolve(query)).lyrics;
        expect(log, isEmpty);
        final controller = LyricsTranslationController(
          lookup: resolver.translate,
        );
        addTearDown(controller.dispose);
        controller.configure(
          lyrics,
          const AppPreferences(lyricsAutoTranslate: false),
          'zh-Hans',
          query: query,
        );
        await controller.translate();
        expect(controller.lines?.first, '闭上双眼 仍能清晰回忆起彼时');
        expect(controller.failed, isFalse);
        expect(log, hasLength(2));
      },
    );

    test(
      'Chinese source translations follow Traditional Chinese interface',
      () async {
        final resolver = LyricsResolver(
          (_) async => official(),
          translation: source(mysteryOfLove),
        );
        final result = await resolver.translate(query, official(), 'zh-TW');
        expect(result?.provider, LyricsProvider.netease);
        expect(result?.lines.first, '閉上雙眼 仍能清晰回憶起彼時');
        expect(official().lines.first.words, originals.first.words);
      },
    );

    test(
      'English target does not query a Chinese-only translation source',
      () async {
        final log = <String>[];
        final resolver = LyricsResolver(
          (_) async => official(),
          translation: source(mysteryOfLove, log: log),
        );
        expect(await resolver.translate(query, official(), 'en'), isNull);
        expect(log, isEmpty);
      },
    );

    test(
      'source failure is retryable, not reported as missing translation',
      () async {
        final resolver = LyricsResolver(
          (_) async => official(),
          translation: source((_) => http.Response('', 403)),
        );
        final controller = LyricsTranslationController(
          lookup: resolver.translate,
        );
        addTearDown(controller.dispose);
        controller.configure(
          official(),
          const AppPreferences(lyricsAutoTranslate: false),
          'zh-Hans',
          query: query,
        );
        await controller.translate();
        expect(controller.failed, isTrue);
        expect(controller.unavailable, isFalse);
      },
    );

    test('官方歌词挂上网易云译文', () async {
      final resolver = LyricsResolver(
        (_) async => official(),
        translation: source(mysteryOfLove),
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.lines.map((l) => l.translation), [
        '闭上双眼 仍能清晰回忆起彼时',
        '最初 那吻印下的时刻',
        '如今我的泪 却旖旎不至尽头',
        '我用我的名字筑起高墙',
      ]);
    });

    test('歌词行已有译文（LRCLIB 对照版）时不查网易云', () async {
      final log = <String>[];
      final bilingual = [
        const LyricLine(startTimeMs: 1000, words: 'hello', translation: '你好'),
        const LyricLine(startTimeMs: 2000, words: 'world', translation: '世界'),
      ];
      final resolver = LyricsResolver(
        (_) async => SpotifyLyrics(lines: bilingual),
        translation: source(mysteryOfLove, log: log),
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.lines.first.translation, '你好');
      expect(log, isEmpty);
    });

    test('译文查询网络错误：原文照常返回但不缓存', () async {
      final resolver = LyricsResolver(
        (_) async => official(),
        translation: source((req) => http.Response('', 503)),
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.lines.first.translation, isEmpty);
      expect(res.cacheable, isFalse);
    });

    test('两句原文时间戳相同：按下标对齐，各拿各的译文', () async {
      final sameTime = [
        const LyricLine(
          startTimeMs: 17780,
          words: 'Oh, to see without my eyes',
        ),
        const LyricLine(
          startTimeMs: 17780,
          words: 'The first time that you kissed me',
        ),
        const LyricLine(
          startTimeMs: 26750,
          words: 'Boundless by the time I cried',
        ),
        const LyricLine(
          startTimeMs: 30820,
          words: 'I built your walls around me',
        ),
      ];
      final resolver = LyricsResolver(
        (_) async => SpotifyLyrics(lines: sameTime),
        translation: source(mysteryOfLove),
      );
      final res = await resolver.resolve(query);
      expect(res.lyrics.lines.map((l) => l.translation), [
        '闭上双眼 仍能清晰回忆起彼时',
        '最初 那吻印下的时刻',
        '如今我的泪 却旖旎不至尽头',
        '我用我的名字筑起高墙',
      ]);
    });

    test('没有译文源时行为与之前一致', () async {
      final resolver = LyricsResolver((_) async => official());
      final res = await resolver.resolve(query);
      expect(res.lyrics.lines.first.translation, isEmpty);
      expect(res.cacheable, isTrue);
    });

    test('双语歌词关闭时不查网易云：一个请求都不发，原文照常返回并可缓存', () async {
      final log = <String>[];
      final resolver = LyricsResolver(
        (_) async => official(),
        translation: source(mysteryOfLove, log: log),
        translationEnabled: () => false,
      );
      final res = await resolver.resolve(query);
      expect(log, isEmpty, reason: '关闭时曲名 / 歌手不能发给网易云');
      expect(
        res.lyrics.lines.map((l) => l.words),
        originals.map((l) => l.words),
      );
      expect(res.lyrics.lines.map((l) => l.translation), everyElement(isEmpty));
      expect(res.cacheable, isTrue);
    });

    test('开关在每次解析时读取：打开后查网易云并挂上译文', () async {
      final log = <String>[];
      var enabled = false;
      final resolver = LyricsResolver(
        (_) async => official(),
        translation: source(mysteryOfLove, log: log),
        translationEnabled: () => enabled,
      );
      await resolver.resolve(query);
      expect(log, isEmpty);

      enabled = true;
      final res = await resolver.resolve(query);
      expect(log, isNotEmpty);
      expect(res.lyrics.lines.first.translation, '闭上双眼 仍能清晰回忆起彼时');
    });
  });
}
