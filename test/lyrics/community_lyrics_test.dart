import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/models/lyrics_source.dart';
import 'package:flutify_app/services/lyrics/community_lyrics.dart';
import 'package:flutify_app/services/lyrics/lyrics_disk_cache.dart';
import 'package:flutify_app/services/lyrics/lyrics_resolver.dart';
import 'package:flutify_app/services/lyrics/translation_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = LyricsQuery(
  trackId: 'track',
  title: 'Paper Stars',
  artist: 'Test Artist',
);

const _lrc = '''
[00:00.00]作词 : Someone
[00:01.00]Paper stars
[00:04.00]Draw a circle
[00:07.00]Count the lights
[00:10.00]Fold them twice
''';

const _tlyric = '''
[00:01.00]纸星星
[00:04.00]画一个圆
[00:07.00]数着灯光
[00:10.00]折叠两次
''';

class _Community implements TranslationSource, OriginalLyricsSource {
  @override
  final LyricsProvider provider;
  @override
  LyricsDiskCache? get cache => null;
  int originalCalls = 0;
  final SpotifyLyrics? lyrics;

  _Community(this.provider, this.lyrics);

  @override
  Future<TranslationSourceLookup> find(
    LyricsQuery query,
    List<LyricLine> originals,
  ) async => const TranslationSourceLookup(null);

  @override
  Future<SourceLyricsLookup> findLyrics(LyricsQuery query) async {
    originalCalls++;
    return SourceLyricsLookup(lyrics);
  }

  @override
  Future<void> forget(LyricsQuery query) async {}
}

void main() {
  group('CommunityLyrics.build', () {
    test('keeps the original lines, drops credits and attaches translations', () {
      final lyrics = CommunityLyrics.build(_lrc, _tlyric, LyricsProvider.qqMusic)!;
      expect(lyrics.provider, LyricsProvider.qqMusic);
      expect(lyrics.translationProvider, LyricsProvider.qqMusic);
      expect(lyrics.lines.map((l) => l.words), [
        'Paper stars',
        'Draw a circle',
        'Count the lights',
        'Fold them twice',
      ]);
      expect(lyrics.lines.map((l) => l.translation), [
        '纸星星',
        '画一个圆',
        '数着灯光',
        '折叠两次',
      ]);
      expect(lyrics.isSynced, isTrue);
    });

    test('without a translation the lyrics stay monolingual', () {
      final lyrics = CommunityLyrics.build(_lrc, '', LyricsProvider.netease)!;
      expect(lyrics.translationProvider, isNull);
      expect(lyrics.lines.every((l) => l.translation.isEmpty), isTrue);
    });

    test('instrumental placeholders are not lyrics', () {
      expect(
        CommunityLyrics.build(
          '[00:00.00]纯音乐，请欣赏\n',
          '',
          LyricsProvider.netease,
        ),
        isNull,
      );
    });
  });

  group('LyricsResolver original lookup', () {
    test('QQ Music can provide the original when it ranks first', () async {
      final qqLyrics = CommunityLyrics.build(
        _lrc,
        _tlyric,
        LyricsProvider.qqMusic,
      );
      final qq = _Community(LyricsProvider.qqMusic, qqLyrics);
      var officialCalls = 0;
      final resolver = LyricsResolver(
        (_) async {
          officialCalls++;
          return const SpotifyLyrics(lines: []);
        },
        qqTranslation: qq,
        sourceOrder: () => [
          LyricsSource.qqMusic,
          LyricsSource.spotify,
          LyricsSource.netease,
          LyricsSource.lrclib,
        ],
      );
      final resolved = await resolver.resolve(_query);
      expect(resolved.lyrics.provider, LyricsProvider.qqMusic);
      expect(resolved.lyrics.lines.first.translation, '纸星星');
      expect(qq.originalCalls, 1);
      expect(officialCalls, 0);
    });

    test('turning fill-in off keeps community sources out of originals', () async {
      final qq = _Community(
        LyricsProvider.qqMusic,
        CommunityLyrics.build(_lrc, _tlyric, LyricsProvider.qqMusic),
      );
      final resolver = LyricsResolver(
        (_) async => const SpotifyLyrics(lines: []),
        qqTranslation: qq,
        fallbackEnabled: () => false,
        translationEnabled: () => false,
      );
      final resolved = await resolver.resolve(_query);
      expect(resolved.lyrics.provider, LyricsProvider.spotify);
      expect(qq.originalCalls, 0);
    });
  });
}
