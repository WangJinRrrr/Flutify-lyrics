import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lrclib_client.dart';
import 'package:flutify_app/services/lyrics/lrclib_lyrics_source.dart';
import 'package:flutify_app/services/lyrics/lyrics_disk_cache.dart';
import 'package:flutify_app/services/lyrics/lyrics_resolver.dart';
import 'package:flutify_app/services/lyrics/lyrics_translation.dart';
import 'package:flutify_app/services/lyrics/translation_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

const query = LyricsQuery(
  trackId: 'paper-stars',
  title: 'Paper Stars',
  artist: 'Test Artist',
);

const synced = SpotifyLyrics(
  language: 'en',
  lines: [
    LyricLine(startTimeMs: 1000, words: 'Paper stars'),
    LyricLine(startTimeMs: 4000, words: 'Draw a circle'),
  ],
);

const lrclibSynced = SpotifyLyrics(
  language: 'en',
  lines: [
    LyricLine(startTimeMs: 1200, words: 'Paper stars (lrclib)'),
    LyricLine(startTimeMs: 4200, words: 'Draw a circle (lrclib)'),
  ],
);

const lrclibFirst = [
  LyricsSource.lrclib,
  LyricsSource.spotify,
  LyricsSource.qqMusic,
  LyricsSource.netease,
];

class FakeSource implements TranslationSource {
  @override
  final LyricsProvider provider;
  @override
  LyricsDiskCache? get cache => null;
  int calls = 0;
  final String text;

  FakeSource(this.provider, this.text);

  @override
  Future<TranslationSourceLookup> find(
    LyricsQuery query,
    List<LyricLine> originals,
  ) async {
    calls++;
    return TranslationSourceLookup([
      LyricLine(startTimeMs: 1000, words: text),
      const LyricLine(startTimeMs: 4000, words: '画一个圆'),
    ]);
  }

  @override
  Future<void> forget(LyricsQuery query) async {}
}

class FakeLrclib extends LrclibLyricsSource {
  SpotifyLyrics? original;
  LyricsTranslation? translation;
  int findCalls = 0;
  int translationCalls = 0;

  FakeLrclib({this.original, this.translation})
    : super(
        LrclibClient(
          MockClient((_) async => throw StateError('unexpected HTTP')),
        ),
      );

  @override
  Future<LrclibLookup> find(LyricsQuery query) async {
    findCalls++;
    return LrclibLookup(original);
  }

  @override
  Future<LyricsTranslation?> findTranslation(
    LyricsQuery query,
    SpotifyLyrics lyrics,
    String target,
  ) async {
    translationCalls++;
    return translation;
  }
}

void main() {
  group('LyricsSource.parseOrder', () {
    test('missing or malformed input falls back to the default order', () {
      for (final raw in [
        null,
        'bad',
        3,
        <Object?>[],
        <Object?>['x', 1],
      ]) {
        expect(LyricsSource.parseOrder(raw), LyricsSource.defaultOrder);
      }
    });

    test('keeps the saved order, drops unknown and duplicate entries', () {
      expect(
        LyricsSource.parseOrder([
          'lrclib',
          'ghost',
          'netease',
          'lrclib',
          'spotify',
        ]),
        [
          LyricsSource.lrclib,
          LyricsSource.netease,
          LyricsSource.spotify,
          LyricsSource.qqMusic,
        ],
      );
    });

    test('result always lists every source exactly once and is immutable', () {
      final order = LyricsSource.parseOrder(['netease']);
      expect(order.toSet(), LyricsSource.values.toSet());
      expect(order.length, LyricsSource.values.length);
      expect(() => order.add(LyricsSource.spotify), throwsUnsupportedError);
    });
  });

  group('AppPreferences.lyricsSourceOrder', () {
    test('defaults to the legacy chain and survives a JSON round trip', () {
      expect(
        const AppPreferences().lyricsSourceOrder,
        LyricsSource.defaultOrder,
      );
      final changed = const AppPreferences().copyWith(
        lyricsSourceOrder: [
          LyricsSource.netease,
          LyricsSource.lrclib,
          LyricsSource.spotify,
          LyricsSource.qqMusic,
        ],
      );
      final restored = AppPreferences.fromJson(changed.toJson());
      expect(restored.lyricsSourceOrder, changed.lyricsSourceOrder);
      expect(restored, changed);
      expect(restored.hashCode, changed.hashCode);
      expect(restored == const AppPreferences(), isFalse);
    });

    test('old preferences without the key keep the default order', () {
      expect(
        AppPreferences.fromJson({}).lyricsSourceOrder,
        LyricsSource.defaultOrder,
      );
    });

    test('copyWith normalizes a partial list', () {
      final prefs = const AppPreferences().copyWith(
        lyricsSourceOrder: [LyricsSource.lrclib],
      );
      expect(prefs.lyricsSourceOrder, [
        LyricsSource.lrclib,
        LyricsSource.spotify,
        LyricsSource.qqMusic,
        LyricsSource.netease,
      ]);
    });
  });

  group('LyricsResolver original lyrics order', () {
    test('default order asks Spotify first and skips LRCLIB', () async {
      final lrclib = FakeLrclib(original: lrclibSynced);
      final resolver = LyricsResolver((_) async => synced, fallback: lrclib);
      final result = await resolver.resolve(query);
      expect(result.lyrics.lines.first.words, 'Paper stars');
      expect(lrclib.findCalls, 0);
    });

    test('LRCLIB first wins and Spotify is never requested', () async {
      var officialCalls = 0;
      final lrclib = FakeLrclib(original: lrclibSynced);
      final resolver = LyricsResolver(
        (_) async {
          officialCalls++;
          return synced;
        },
        fallback: lrclib,
        sourceOrder: () => lrclibFirst,
      );
      final result = await resolver.resolve(query);
      expect(result.lyrics.lines.first.words, 'Paper stars (lrclib)');
      expect(lrclib.findCalls, 1);
      expect(officialCalls, 0);
    });

    test(
      'LRCLIB first falls through to Spotify when it finds nothing',
      () async {
        final lrclib = FakeLrclib();
        final resolver = LyricsResolver(
          (_) async => synced,
          fallback: lrclib,
          sourceOrder: () => lrclibFirst,
        );
        final result = await resolver.resolve(query);
        expect(result.lyrics.lines.first.words, 'Paper stars');
        expect(lrclib.findCalls, 1);
      },
    );

    test('disabled LRCLIB is skipped even when ranked first', () async {
      final lrclib = FakeLrclib(original: lrclibSynced);
      final resolver = LyricsResolver(
        (_) async => synced,
        fallback: lrclib,
        fallbackEnabled: () => false,
        sourceOrder: () => lrclibFirst,
      );
      final result = await resolver.resolve(query);
      expect(result.lyrics.lines.first.words, 'Paper stars');
      expect(lrclib.findCalls, 0);
    });

    test('an order change takes effect on the next query', () async {
      var order = LyricsSource.defaultOrder;
      final lrclib = FakeLrclib(original: lrclibSynced);
      final resolver = LyricsResolver(
        (_) async => synced,
        fallback: lrclib,
        sourceOrder: () => order,
      );
      expect(
        (await resolver.resolve(query)).lyrics.lines.first.words,
        'Paper stars',
      );
      order = lrclibFirst;
      expect(
        (await resolver.resolve(query)).lyrics.lines.first.words,
        'Paper stars (lrclib)',
      );
    });

    test('Spotify errors still surface when nothing else has lyrics', () async {
      final resolver = LyricsResolver(
        (_) async => throw StateError('offline'),
        fallback: FakeLrclib(),
        sourceOrder: () => lrclibFirst,
      );
      await expectLater(resolver.resolve(query), throwsStateError);
    });
  });

  group('LyricsResolver translation order', () {
    late FakeSource qq;
    late FakeSource netease;
    setUp(() {
      qq = FakeSource(LyricsProvider.qqMusic, '纸星星');
      netease = FakeSource(LyricsProvider.netease, '纸做的星星');
    });

    test('NetEase ranked above QQ is asked first', () async {
      final resolver = LyricsResolver(
        (_) async => synced,
        qqTranslation: qq,
        translation: netease,
        sourceOrder: () => [
          LyricsSource.spotify,
          LyricsSource.netease,
          LyricsSource.qqMusic,
          LyricsSource.lrclib,
        ],
      );
      final result = await resolver.translate(query, synced, 'zh');
      expect(result?.provider, LyricsProvider.netease);
      expect(netease.calls, 1);
      expect(qq.calls, 0);
    });

    test('LRCLIB ranked first is used before the Chinese sources', () async {
      final lrclib = FakeLrclib(
        translation: const LyricsTranslation([
          '纸星星(lrclib)',
          '画一个圆(lrclib)',
        ], LyricsProvider.lrclib),
      );
      final resolver = LyricsResolver(
        (_) async => synced,
        fallback: lrclib,
        qqTranslation: qq,
        translation: netease,
        sourceOrder: () => lrclibFirst,
      );
      final result = await resolver.translate(query, synced, 'zh');
      expect(result?.provider, LyricsProvider.lrclib);
      expect(lrclib.translationCalls, 1);
      expect(qq.calls, 0);
      expect(netease.calls, 0);
    });

    test('disabled LRCLIB translation is skipped regardless of rank', () async {
      final lrclib = FakeLrclib();
      final resolver = LyricsResolver(
        (_) async => synced,
        fallback: lrclib,
        fallbackEnabled: () => false,
        qqTranslation: qq,
        translation: netease,
        sourceOrder: () => lrclibFirst,
      );
      final result = await resolver.translate(query, synced, 'zh');
      expect(result?.provider, LyricsProvider.qqMusic);
      expect(lrclib.translationCalls, 0);
    });

    test('non-Chinese targets never ask QQ or NetEase', () async {
      final lrclib = FakeLrclib();
      final resolver = LyricsResolver(
        (_) async => synced,
        fallback: lrclib,
        qqTranslation: qq,
        translation: netease,
      );
      await resolver.translate(query, synced, 'ja');
      expect(qq.calls, 0);
      expect(netease.calls, 0);
      expect(lrclib.translationCalls, 1);
    });
  });
}
