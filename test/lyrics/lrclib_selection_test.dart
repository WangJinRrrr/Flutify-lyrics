import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/artist_match.dart';
import 'package:flutify_app/services/lyrics/lrclib_candidate.dart';
import 'package:flutify_app/services/lyrics/lrclib_selector.dart';
import 'package:flutify_app/services/lyrics/lyric_script.dart';
import 'package:flutify_app/services/lyrics/translation_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// LRCLIB 选词：翻译版排除、原唱语言投票、简繁对齐（合成候选）。
void main() {
  const english =
      '[00:01.00]walking down the road\n[00:03.00]under the sky\n[00:05.00]all night long\n'
      '[00:07.00]you and me';
  const chinese =
      '[00:01.00]走在路上\n[00:03.00]天空下面\n[00:05.00]整夜不停\n[00:07.00]你和我';
  const japanese =
      '[00:01.00]道を歩いて\n[00:03.00]空の下で\n[00:05.00]夜通しずっと\n[00:07.00]君とわたし';
  const bilingual =
      '[00:01.00]walking down the road\n[00:01.10]走在路上\n[00:03.00]under the sky\n'
      '[00:03.10]天空下面\n[00:05.00]all night long\n[00:05.10]整夜不停';

  LrclibCandidate candidate(
    String synced, {
    String title = 'Road',
    double duration = 200,
    String artist = '',
  }) => LrclibCandidate(
    trackName: title,
    artistName: artist,
    synced: synced,
    duration: duration,
  );

  const query = LyricsQuery(
    trackId: 't',
    title: 'Road',
    artist: 'Someone',
    durationMs: 200000,
  );

  group('TranslationFilter', () {
    test('曲名带翻译标记且与当前曲名不同时排除', () {
      expect(
        TranslationFilter.isRejected(
          candidate(chinese, title: 'Road (中文翻译)'),
          'Road',
        ),
        isTrue,
      );
    });

    test('曲名完全一致时不因标记误杀', () {
      expect(
        TranslationFilter.isRejected(
          candidate(english, title: 'Lost in Translation'),
          'Lost in Translation',
        ),
        isFalse,
      );
    });

    test('同时间点双语对照不再排除（可用：拆成原文 + 译文）', () {
      expect(
        TranslationFilter.isRejected(candidate(bilingual), 'Road'),
        isFalse,
      );
      expect(TranslationFilter.isRejected(candidate(english), 'Road'), isFalse);
    });

    test('整首混排又拆不出逐句对照才排除', () {
      const mixed =
          '[00:01.00]first verse in english\n[00:03.00]second line here\n'
          '[00:05.00]第三句开始中文\n[00:07.00]第四句中文歌词';
      expect(TranslationFilter.isRejected(candidate(mixed), 'Road'), isTrue);
    });
  });

  group('LrclibSelector', () {
    test('多数候选的语言胜出：英文歌不会配上少数的译词', () {
      final picked = LrclibSelector.select([
        candidate(chinese),
        candidate(english),
        candidate(english),
      ], query);
      expect(picked?.lang, LyricLang.latin);
      expect(picked?.synced, english);
    });

    test('日文原词占多数时选日文', () {
      final picked = LrclibSelector.select([
        candidate(japanese),
        candidate(japanese),
        candidate(english),
      ], query);
      expect(picked?.lang, LyricLang.ja);
    });

    test('时长差太多的候选降权', () {
      final picked = LrclibSelector.select([
        candidate(english, duration: 400),
        candidate(english.replaceAll('road', 'street')),
      ], query);
      expect(picked?.synced, contains('street'));
    });

    test('只剩被排除的版本时退而求其次', () {
      final picked = LrclibSelector.select([
        candidate(english, title: 'Road (中文翻译)'),
      ], query);
      expect(picked, isNotNull);
    });

    test('双语对照作为唯一候选时选中，歌曲语言按原文部分判定', () {
      final picked = LrclibSelector.select([candidate(bilingual)], query);
      expect(picked, isNotNull);
      expect(picked?.lang, LyricLang.latin, reason: '投票只看拆分出的英文原文，不掺中文译文');
    });

    test('繁体曲名的歌把简体歌词转成繁体', () {
      const zhQuery = LyricsQuery(
        trackId: 't',
        title: '說話的時候',
        artist: '某人',
        durationMs: 200000,
      );
      const simplified =
          '[00:01.00]说话的时候\n[00:03.00]这里会响\n[00:05.00]听见声音\n[00:07.00]东边门开';
      final picked = LrclibSelector.select([
        candidate(simplified, title: '說話的時候'),
      ], zhQuery);
      expect(picked?.lang, LyricLang.zh);
      expect(picked?.synced, contains('說話'));
    });

    test('没有候选返回 null', () => expect(LrclibSelector.select([], query), isNull));

    group('纯音乐守卫', () {
      LrclibCandidate instrumental({
        String title = 'Road',
        double duration = 200,
        String artist = 'Someone',
      }) => LrclibCandidate(
        trackName: title,
        artistName: artist,
        synced: '',
        duration: duration,
        instrumental: true,
      );

      test('精确吻合的纯音乐记录存在时不上歌词（同名带词歌也不能用）', () {
        // 当前曲目是纯音乐（LRCLIB 有吻合的纯音乐记录），另有同名歌曲的带词记录
        final otherSong = candidate(english, artist: 'Another Singer');
        expect(
          LrclibSelector.select([instrumental(), otherSong], query),
          isNull,
        );
      });

      test('纯音乐记录与带词记录都精确吻合时，带词的优先', () {
        final mine = candidate(english, artist: 'Someone');
        final picked = LrclibSelector.select([instrumental(), mine], query);
        expect(picked?.synced, english);
      });

      test('纯音乐记录不精确（时长差太多 / 歌手不同）时不影响正常选词', () {
        final farAway = instrumental(duration: 500);
        final otherArtist = instrumental(artist: 'Delta Band');
        final mine = candidate(english, artist: 'Someone');
        expect(LrclibSelector.select([farAway, mine], query)?.synced, english);
        expect(
          LrclibSelector.select([otherArtist, mine], query)?.synced,
          english,
        );
      });

      test('LRCLIB 的纯音乐记录没有歌词字段也能解析（否则守卫永远看不到它）', () {
        final parsed = LrclibCandidate.fromJson({
          'trackName': 'Road',
          'artistName': 'Someone',
          'duration': 200,
          'instrumental': true,
        });
        expect(parsed, isNotNull);
        expect(parsed!.instrumental, isTrue);
        expect(parsed.lines, isEmpty);
      });
    });

    test('歌手对不上的同名歌即使时长吻合也不用', () {
      const q = LyricsQuery(
        trackId: 't',
        title: 'Road',
        artist: 'Alpha & Beta, Gamma',
        durationMs: 200000,
      );
      final other = candidate(english, artist: 'Delta Band');
      final mine = candidate(
        english.replaceAll('road', 'street'),
        artist: 'Alpha, Beta',
        duration: 210,
      );
      expect(
        LrclibSelector.select([other, mine], q)?.synced,
        contains('street'),
      );
      expect(LrclibSelector.select([other], q), isNull, reason: '配错歌比没有歌词更糟');
    });

    test('歌手文字不同（本地化译名）时不排除', () {
      const q = LyricsQuery(
        trackId: 't',
        title: '路',
        artist: '某歌手',
        durationMs: 200000,
      );
      expect(
        LrclibSelector.select([
          candidate(chinese, title: '路', artist: 'Some Singer'),
        ], q),
        isNotNull,
      );
    });

    group('歌手信息缺失（远程曲目未补全等）', () {
      // 真实案例：纯音乐「My Way / OAO / 130s」在歌手缺失时被配上 Frank Sinatra 的同名歌词
      const noArtist = LyricsQuery(
        trackId: 't',
        title: 'My Way',
        artist: '',
        durationMs: 130000,
      );

      test('只接受曲名一致且时长吻合的候选', () {
        final sinatra = candidate(
          english,
          title: 'My Way',
          duration: 280,
          artist: 'Frank Sinatra',
        );
        final close = candidate(
          english.replaceAll('road', 'street'),
          title: 'My Way',
          duration: 131,
        );
        expect(
          LrclibSelector.select([sinatra], noArtist),
          isNull,
          reason: '时长差 150s，是另一首歌',
        );
        expect(
          LrclibSelector.select([sinatra, close], noArtist)?.synced,
          contains('street'),
        );
      });

      test('时长也缺失时不上歌词', () {
        const bare = LyricsQuery(trackId: 't', title: 'My Way', artist: '');
        final sinatra = candidate(
          english,
          title: 'My Way',
          duration: 280,
          artist: 'Frank Sinatra',
        );
        expect(LrclibSelector.select([sinatra], bare), isNull);
      });
    });
  });

  group('ArtistMatcher', () {
    test('多位艺人拆分、忽略大小写与标点', () {
      expect(
        ArtistMatcher.compare('GAMPER & DADONI, ILIRA', 'Gamper, Dadoni'),
        ArtistMatch.match,
      );
      expect(
        ArtistMatcher.compare('Alpha', 'Alpha feat. Beta'),
        ArtistMatch.match,
      );
      expect(
        ArtistMatcher.compare('Tiësto', 'Tiësto, Someone Else'),
        ArtistMatch.match,
      );
      expect(
        ArtistMatcher.compare('Alpha & Beta', 'Delta Band'),
        ArtistMatch.mismatch,
      );
    });

    test('繁简统一后比较；文字不同或为空时无法判断', () {
      expect(ArtistMatcher.compare('陈奕迅', '陳奕迅'), ArtistMatch.match);
      expect(ArtistMatcher.compare('某歌手', 'Some Singer'), ArtistMatch.unknown);
      expect(ArtistMatcher.compare('', 'Alpha'), ArtistMatch.unknown);
    });
  });
}
