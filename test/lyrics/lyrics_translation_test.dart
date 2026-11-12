import 'dart:async';
import 'dart:convert';

import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lrclib_candidate.dart';
import 'package:flutify_app/services/lyrics/lrclib_client.dart';
import 'package:flutify_app/services/lyrics/lrclib_lyrics_source.dart';
import 'package:flutify_app/services/lyrics/lrclib_translation.dart';
import 'package:flutify_app/services/lyrics/lyrics_language.dart';
import 'package:flutify_app/services/lyrics/lyrics_translation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const query = LyricsQuery(
  trackId: 'one',
  title: 'Song',
  artist: 'Singer',
  durationMs: 180000,
);
const original = SpotifyLyrics(
  language: 'en',
  lines: [
    LyricLine(startTimeMs: 1000, words: 'First line'),
    LyricLine(startTimeMs: 2500, words: ''),
    LyricLine(startTimeMs: 4000, words: 'Second line'),
    LyricLine(startTimeMs: 8000, words: 'Third line'),
  ],
);
const hans = ['这里有风', '', '听见你的声音', '这是最后一行'];
const hant = ['這裡有風', '', '聽見你的聲音', '這是最後一行'];
final withAlternatives = SpotifyLyrics(
  language: 'en',
  lines: original.lines,
  alternatives: const [
    LyricsAlternative(language: 'zh-Hant', lines: hant),
    LyricsAlternative(language: 'zh-CN', lines: hans),
  ],
);

void main() {
  test(
    'community inline translations retain provenance and follow Chinese script',
    () {
      final lyrics = SpotifyLyrics(
        language: 'en',
        provider: LyricsProvider.lrclib,
        translationProvider: LyricsProvider.netease,
        lines: [
          for (final (i, line) in original.lines.indexed)
            LyricLine(
              startTimeMs: line.startTimeMs,
              words: line.words,
              translation: hans[i],
            ),
        ],
      );
      final selected = LyricsTranslationController.official(lyrics, 'zh-Hans');
      expect(selected?.lines, hans);
      expect(selected?.provider, LyricsProvider.netease);
      expect(LyricsTranslationController.official(lyrics, 'zh-Hant'), isNull);
      expect(LyricsTranslationController.official(lyrics, 'ja'), isNull);
    },
  );

  test(
    'Japanese interface selects Japanese source translation and excludes Japanese originals',
    () {
      const japanese = ['ここには風がある', '', '君の声が聞こえる', 'これが最後の行'];
      final controller = LyricsTranslationController();
      addTearDown(controller.dispose);
      controller.configure(
        SpotifyLyrics(
          language: 'en',
          lines: original.lines,
          alternatives: const [
            LyricsAlternative(language: 'ja', lines: japanese),
            LyricsAlternative(language: 'zh-CN', lines: hans),
          ],
        ),
        AppPreferences.defaults,
        'ja-JP',
        query: query,
      );
      expect(controller.lines, japanese);
      controller.configure(
        const SpotifyLyrics(
          language: 'ja',
          lines: [LyricLine(startTimeMs: 0, words: 'ここには風がある')],
        ),
        AppPreferences.defaults,
        'ja-JP',
        query: query,
      );
      expect(controller.lines, isNull);
      expect(controller.busy, isFalse);
    },
  );
  test(
    'Spotify alternatives parse, survive JSON round trip, and preserve blanks',
    () {
      final data = withAlternatives.toJson();
      data['alternatives'] = <Object?>[
        ...data['alternatives'] as List,
        {
          'language': 'en',
          'lines': [1],
        },
        {
          'lines': ['missing language'],
        },
        null,
      ];
      final lyrics = SpotifyLyrics.fromJson({'lyrics': data});
      expect(lyrics.alternatives, hasLength(2));
      expect(
        LyricsTranslationController.official(lyrics, 'zh-Hans')?.lines,
        hans,
      );
      expect(
        LyricsTranslationController.official(lyrics, 'zh-TW')?.lines,
        hant,
      );
      expect(
        SpotifyLyrics.fromJson(lyrics.toJson()).alternatives.first.lines[1],
        '',
      );
    },
  );

  test(
    'Spotify mismatched line counts and opposite Chinese script are rejected',
    () {
      final lyrics = SpotifyLyrics(
        lines: original.lines,
        alternatives: const [
          LyricsAlternative(language: 'zh-Hans', lines: ['一行']),
          LyricsAlternative(language: 'zh-Hant', lines: hant),
        ],
      );
      expect(LyricsTranslationController.official(lyrics, 'zh-Hans'), isNull);
      final generic = SpotifyLyrics(
        lines: original.lines,
        alternatives: const [LyricsAlternative(language: 'zh', lines: hant)],
      );
      expect(LyricsTranslationController.official(generic, 'zh-Hans'), isNull);
      expect(
        LyricsTranslationController.official(generic, 'zh-Hant')?.lines,
        hant,
      );
    },
  );

  test('Chinese aliases and exclusions retain script distinctions', () {
    expect(LyricsLanguage.normalize('zh_HK'), 'zh-Hant');
    expect(LyricsLanguage.normalize('zh-SG'), 'zh-Hans');
    expect(LyricsLanguage.excluded('zh-Hant', 'zh-Hans'), isFalse);
    expect(LyricsLanguage.excluded('zh-Hant', 'zh'), isTrue);
    expect(LyricsLanguage.of('zh', hans.join()), 'zh-Hans');
    expect(LyricsLanguage.of('zh', hant.join()), 'zh-Hant');
    expect(LyricsLanguage.of('und', 'Bonjour le monde'), 'und');
  });

  test(
    'auto selection follows interface script, cancel lasts for current track',
    () async {
      final controller = LyricsTranslationController();
      addTearDown(controller.dispose);
      controller.configure(
        withAlternatives,
        AppPreferences.defaults,
        'zh-CN',
        query: query,
      );
      expect(controller.lines, hans);
      controller.configure(
        withAlternatives,
        AppPreferences.defaults,
        'zh-Hant',
        query: query,
      );
      expect(controller.lines, hant);
      controller.cancel();
      controller.configure(
        withAlternatives,
        AppPreferences.defaults,
        'zh-Hant',
        query: query,
      );
      expect(controller.lines, isNull);
      await controller.translate();
      expect(controller.lines, hant);
      controller.cancel();
      controller.configure(
        withAlternatives,
        AppPreferences.defaults,
        'zh-Hant',
        query: const LyricsQuery(
          trackId: 'two',
          title: 'Other',
          artist: 'Singer',
        ),
      );
      expect(controller.lines, hant);
    },
  );

  test(
    'auto off and exclusions suppress lookup but allow manual selection',
    () async {
      final controller = LyricsTranslationController();
      addTearDown(controller.dispose);
      controller.configure(
        withAlternatives,
        AppPreferences.defaults.copyWith(lyricsAutoTranslate: false),
        'zh-CN',
        query: query,
      );
      expect(controller.lines, isNull);
      await controller.translate();
      expect(controller.lines, hans);
      controller.configure(
        withAlternatives,
        AppPreferences.defaults.copyWith(lyricsExcludedLanguages: ['en']),
        'zh-CN',
        query: query,
      );
      expect(controller.lines, isNull);
      await controller.translate();
      expect(controller.lines, hans);
      final chineseOriginal = SpotifyLyrics(
        language: 'zh',
        lines: [
          for (var i = 0; i < hans.length; i++)
            LyricLine(startTimeMs: i * 1000, words: hans[i]),
        ],
        alternatives: const [
          LyricsAlternative(language: 'zh-Hant', lines: hant),
        ],
      );
      controller.configure(
        chineseOriginal,
        AppPreferences.defaults,
        'zh-Hans',
        query: query,
      );
      expect(controller.lines, isNull);
      controller.configure(
        chineseOriginal,
        AppPreferences.defaults,
        'zh-Hant',
        query: query,
      );
      expect(controller.lines, hant);
    },
  );

  test(
    'cancel and track change discard late asynchronous translations',
    () async {
      final requests = <Completer<LyricsTranslation?>>[];
      final controller = LyricsTranslationController(
        lookup: (_, _, _) {
          final request = Completer<LyricsTranslation?>();
          requests.add(request);
          return request.future;
        },
      );
      addTearDown(controller.dispose);
      controller.configure(
        original,
        AppPreferences.defaults,
        'zh-CN',
        query: query,
      );
      expect(controller.busy, isTrue);
      controller.cancel();
      requests[0].complete(
        const LyricsTranslation(hans, LyricsProvider.lrclib),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.lines, isNull);
      expect(controller.busy, isFalse);
      final pending = controller.translate();
      controller.configure(
        withAlternatives,
        AppPreferences.defaults,
        'zh-Hant',
        query: const LyricsQuery(
          trackId: 'two',
          title: 'Other',
          artist: 'Singer',
        ),
      );
      requests[1].complete(
        const LyricsTranslation(hans, LyricsProvider.lrclib),
      );
      await pending;
      expect(controller.lines, hant);
    },
  );

  test('network failure and missing translation both allow retry', () async {
    var calls = 0;
    final controller = LyricsTranslationController(
      lookup: (_, _, _) async {
        if (++calls == 1) throw StateError('offline');
        return calls == 2
            ? null
            : const LyricsTranslation(hans, LyricsProvider.lrclib);
      },
    );
    addTearDown(controller.dispose);
    controller.configure(
      original,
      AppPreferences.defaults.copyWith(lyricsAutoTranslate: false),
      'zh-CN',
      query: query,
    );
    await controller.translate();
    expect(controller.failed, isTrue);
    expect(controller.available, isTrue);
    await controller.translate();
    expect(controller.failed, isFalse);
    expect(controller.available, isTrue);
    expect(controller.unavailable, isTrue);
    await controller.translate();
    expect(controller.lines, hans);
    expect(controller.unavailable, isFalse);
  });

  LrclibCandidate candidate({
    String artist = 'Singer',
    String title = 'Song',
    double duration = 180,
    bool bilingual = false,
    List<String> translation = hans,
    int offset = 0,
  }) => LrclibCandidate(
    trackName: title,
    artistName: artist,
    duration: duration,
    synced: [
      for (final i in [0, 2, 3])
        '${bilingual ? '[00:${((original.lines[i].startTimeMs + offset) / 1000).toStringAsFixed(2)}]${original.lines[i].words}\n' : ''}'
            '[00:${((original.lines[i].startTimeMs + offset) / 1000).toStringAsFixed(2)}]${translation[i]}',
    ].join('\n'),
  );

  test(
    'LRCLIB bilingual and translated timelines align without losing blank lines',
    () {
      expect(
        LrclibTranslation.select(
          [candidate(bilingual: true)],
          query,
          original,
          'zh-Hans',
        )?.lines,
        hans,
      );
      expect(
        LrclibTranslation.select(
          [candidate(title: 'Song (Chinese translation)')],
          query,
          original,
          'zh-Hans',
        )?.lines,
        hans,
      );
      expect(
        LrclibTranslation.select(
          [candidate(translation: hant), candidate()],
          query,
          original,
          'zh-Hant',
        )?.lines,
        hant,
      );
    },
  );

  test(
    'LRCLIB rejects wrong artist, version, timeline, script and romanization',
    () {
      for (final wrong in [
        candidate(artist: 'Someone Else'),
        candidate(title: 'Song (Live)'),
        candidate(duration: 200),
        candidate(offset: 900),
        candidate(translation: hant),
        candidate(
          translation: ['zhe li you feng', '', 'ting jian ni', 'zui hou'],
        ),
        candidate(artist: ''),
      ]) {
        expect(
          LrclibTranslation.select([wrong], query, original, 'zh-Hans'),
          isNull,
        );
      }
      expect(
        LrclibTranslation.select(
          [candidate()],
          query,
          SpotifyLyrics(syncType: 'UNSYNCED', lines: original.lines),
          'zh-Hans',
        ),
        isNull,
      );
    },
  );

  test('LRCLIB ignores featured credits but retains version labels', () {
    const featuredQuery = LyricsQuery(
      trackId: 'featured',
      title: 'Song (feat. Guest)',
      artist: 'Singer, Guest',
      durationMs: 180000,
    );
    expect(
      LrclibTranslation.select(
        [candidate()],
        featuredQuery,
        original,
        'zh-Hans',
      )?.lines,
      hans,
    );
    expect(
      LrclibTranslation.select(
        [candidate(title: 'Song (Live)')],
        featuredQuery,
        original,
        'zh-Hans',
      ),
      isNull,
    );
    expect(
      LrclibTranslation.select(
        [candidate(title: 'Song (feat. Guest) (Chinese translation)')],
        query,
        original,
        'zh-Hans',
      )?.lines,
      hans,
    );
  });

  test(
    'Japanese translations retain kanji-only lines without accepting Chinese',
    () {
      const japanese = ['ここには風がある', '', '君の声が聞こえる', '永遠'];
      expect(
        LrclibTranslation.select(
          [candidate(translation: japanese)],
          query,
          original,
          'ja',
        )?.lines,
        japanese,
      );
      expect(
        LrclibTranslation.select([candidate()], query, original, 'ja'),
        isNull,
      );
    },
  );

  test('LRCLIB searches a title without featured artist credits', () async {
    final requests = <Uri>[];
    final source = LrclibLyricsSource(
      LrclibClient(
        MockClient((request) async {
          requests.add(request.url);
          final value = candidate();
          final found =
              request.url.path.endsWith('/search') &&
              request.url.queryParameters['track_name'] == 'Song';
          return http.Response(
            jsonEncode(
              found
                  ? [
                      {
                        'trackName': value.trackName,
                        'artistName': value.artistName,
                        'duration': value.duration,
                        'syncedLyrics': value.synced,
                      },
                    ]
                  : [],
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
      sleep: (_) async {},
    );
    final result = await source.findTranslation(
      const LyricsQuery(
        title: 'Song (feat. Guest)',
        trackId: 'featured',
        artist: 'Singer',
        durationMs: 180000,
      ),
      original,
      'zh-Hans',
    );
    expect(result?.lines, hans);
    expect(requests.first.queryParameters['track_name'], 'Song (feat. Guest)');
    expect(
      requests
          .where((uri) => uri.path.endsWith('/search'))
          .first
          .queryParameters['track_name'],
      'Song',
    );
  });

  test(
    'LRCLIB candidate requests coalesce, cache both scripts, and refetch after forget',
    () async {
      var calls = 0;
      Future<void> noSleep(Duration _) async {}
      final source = LrclibLyricsSource(
        LrclibClient(
          MockClient((request) async {
            calls++;
            final values = [candidate(), candidate(translation: hant)];
            return http.Response(
              jsonEncode([
                for (final value in values)
                  {
                    'trackName': value.trackName,
                    'artistName': value.artistName,
                    'duration': value.duration,
                    'syncedLyrics': value.synced,
                  },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          sleep: noSleep,
        ),
        sleep: noSleep,
      );
      final results = await Future.wait([
        source.findTranslation(query, original, 'zh-Hans'),
        source.findTranslation(query, original, 'zh-Hant'),
      ]);
      expect(results[0]?.lines, hans);
      expect(results[1]?.lines, hant);
      expect(calls, 3);
      await source.findTranslation(query, original, 'zh-Hans');
      expect(calls, 3);
      await source.forget(query);
      await source.findTranslation(query, original, 'zh-Hans');
      expect(calls, 6);
    },
  );
}
