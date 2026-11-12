import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'artist_match.dart';
import 'lrclib_candidate.dart';
import 'lyric_script.dart';
import 'lyrics_language.dart';
import 'lyrics_title.dart';
import 'lyrics_translation.dart';
import 'zh_script.dart';

/// LRCLIB has no translation endpoint or reliable language field. Other-language
/// records must match the song and its timeline; arbitrary line-index pairing is
/// never safe. Bilingual records also provide original-text anchors.
class LrclibTranslation {
  LrclibTranslation._();

  static String _text(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static String _title(String value) => _text(
    ZhScript.convert(
      LyricsTitle.search(
        value.replaceAll(
          RegExp(
            r'\s*(?:[-–—]\s*|[\[(（【])(?:simplified chinese|traditional chinese|chinese|english|japanese|中文|日本語|日语|日語|简体中文|繁體中文|简体|繁體|简中|繁中)?\s*(?:translation|translated|翻译|翻譯|中译|中譯|译词|譯詞|双语|雙語|訳|訳詞)(?:\s*[\])）】])?\s*$',
            caseSensitive: false,
          ),
          '',
        ),
      ),
      toSimplified: true,
    ),
  );

  static LyricsTranslation? select(
    List<LrclibCandidate> candidates,
    LyricsQuery query,
    SpotifyLyrics original,
    String target,
  ) {
    if (!original.isSynced) return null;
    final wanted = LyricsLanguage.normalize(target);
    List<String>? best;
    var bestScore = -1;
    for (final candidate in candidates) {
      if (candidate.instrumental ||
          _title(candidate.trackName) != _title(query.title))
        continue;
      final artist = ArtistMatcher.compare(query.artist, candidate.artistName);
      if (artist == ArtistMatch.mismatch) continue;
      if (query.durationMs > 0 &&
          candidate.duration > 0 &&
          (candidate.duration * 1000 - query.durationMs).abs() > 3000)
        continue;
      final groups = <int, List<String>>{};
      for (final line in candidate.lines) {
        if (line.words.trim().isNotEmpty) {
          groups.putIfAbsent(line.startTimeMs, () => []).add(line.words.trim());
        }
      }
      final result = List.filled(original.lines.length, '');
      final used = <int>{};
      var matched = 0, anchors = 0, nonempty = 0;
      for (var i = 0; i < original.lines.length; i++) {
        final line = original.lines[i];
        if (_text(line.words).isEmpty) continue;
        nonempty++;
        final exact =
            groups.containsKey(line.startTimeMs) &&
            !used.contains(line.startTimeMs);
        final times = exact
            ? [line.startTimeMs]
            : groups.keys
                  .where(
                    (time) =>
                        !used.contains(time) &&
                        (time - line.startTimeMs).abs() <= 350,
                  )
                  .toList();
        // Ambiguous adjacent timestamps are safer to omit than guess.
        if (times.length != 1) continue;
        final time = times.single;
        final words = groups[time]!;
        final anchored = words.any((word) => _text(word) == _text(line.words));
        final translated = words
            .where(
              (word) =>
                  _text(word) != _text(line.words) &&
                  _targetText(word, wanted, candidate),
            )
            .toList();
        if (translated.length != 1) continue;
        used.add(time);
        result[i] = translated.single;
        matched++;
        if (anchored) anchors++;
      }
      if (nonempty < 3 || matched < 3 || matched / nonempty < 0.8) continue;
      final bilingual = anchors / matched >= 0.8;
      if (!bilingual) {
        // Pure translated LRC requires known artist/duration, full alignment,
        // and no extra sung lines (a different edit/version must not slip in).
        if (artist != ArtistMatch.match ||
            query.durationMs <= 0 ||
            candidate.duration <= 0 ||
            matched != nonempty ||
            groups.length != nonempty ||
            groups.values.any((g) => g.length != 1))
          continue;
      }
      final language = LyricsLanguage.of(
        wanted.startsWith('zh')
            ? 'zh'
            : wanted == 'ja'
            ? 'und'
            : wanted,
        result.join('\n'),
      );
      if (!LyricsLanguage.matches(language, wanted)) continue;
      final score = matched + anchors * 2;
      if (score > bestScore) {
        bestScore = score;
        best = result;
      }
    }
    return best == null
        ? null
        : LyricsTranslation(List.unmodifiable(best), LyricsProvider.lrclib);
  }

  static bool _targetText(
    String text,
    String target,
    LrclibCandidate candidate,
  ) {
    final counts = ScriptCounts.of(text);
    if (target.startsWith('zh')) {
      return counts[Script.han] > 0 &&
          counts[Script.kana] == 0 &&
          counts[Script.hangul] == 0 &&
          LyricsLanguage.matches(LyricsLanguage.chineseScript(text), target);
    }
    // Japanese lines can contain only kanji. The assembled translation must
    // still identify as Japanese (including kana), checked above.
    if (target == 'ja') {
      return counts[Script.hangul] == 0 &&
          (counts[Script.kana] > 0 || counts[Script.han] > 0);
    }
    if (target == 'ko') return counts[Script.hangul] > 0;
    // Latin letters alone cannot distinguish English from other languages or
    // romanization: require an explicit translation label in the record.
    if (target == 'en') {
      final metadata = '${candidate.trackName}\n${candidate.synced}';
      return lyricLang(text) == LyricLang.latin &&
          RegExp(
            r'english\s+(?:translation|translated)|(?:translation|translated)\s*[:：]?\s*english|英译|英譯',
            caseSensitive: false,
          ).hasMatch(metadata);
    }
    return false;
  }
}
