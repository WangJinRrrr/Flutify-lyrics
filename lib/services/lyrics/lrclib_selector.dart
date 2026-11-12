import '../../models/lyrics_query.dart';
import 'artist_match.dart';
import 'lrclib_candidate.dart';
import 'lyric_script.dart';
import 'translation_filter.dart';
import 'zh_script.dart';
import 'lyrics_title.dart';

/// 选中的歌词：LRC 原文（已按需转换简繁）与判定出的歌曲语言。
class LrclibSelection {
  final String synced;
  final LyricLang lang;

  const LrclibSelection(this.synced, this.lang);
}

/// 从 LRCLIB 的多份候选里挑出「原唱语言」的那份同步歌词（移植自「任务栏歌词」）。
///
/// 规则：
/// - 歌曲语言 = 原唱语言，以同一首歌候选歌词中占多数的语言为准——原词在库里份数最多，译文 / 音译是少数；
///   曲名 / 歌手只作平局参考（Spotify 会本地化歌手名，J-pop 也常用英文曲名，单看它们会把英文歌配上日文译词）；
///   双语对照候选先拆分（见 `translation_merge.dart`），投票 / 打分只看原文部分；
/// - 歌手对不上（[ArtistMatcher]，同名的另一首歌）直接排除：配错歌比没有歌词更糟；
/// - 翻译版、罗马音、整体混排（[TranslationFilter]）降到「退而求其次」档，只有别无选择时才用；
/// - 打分：语言吻合为主项，歌手对上、曲名一致、时长接近加分；中文再按曲名 / 歌手的字形对齐简繁。
class LrclibSelector {
  LrclibSelector._();

  /// 歌手可比且对不上的候选。
  static bool _otherArtist(LrclibCandidate c, LyricsQuery query) =>
      ArtistMatcher.compare(query.artist, c.artistName) == ArtistMatch.mismatch;

  /// 曲名 + 歌手里繁体专用字多于简体时，认为这首歌要繁体歌词。
  static bool wantsTraditional(LyricsQuery query) {
    final meta = '${query.title} ${query.artist}';
    final trad = ZhScript.countTraditional(meta);
    return trad > 0 && trad > ZhScript.countSimplified(meta);
  }

  static LrclibSelection? select(List<LrclibCandidate> all, LyricsQuery query) {
    var candidates = [
      for (final c in all)
        if (!_otherArtist(c, query)) c,
    ];
    final title = query.title;
    final durSec = query.durationMs / 1000;

    // 歌手信息缺失（如 Connect 远程曲目尚未补全）时撞名歌极多：
    // 只接受曲名一致且时长吻合（±5s）的候选；时长也缺失时宁可不上歌词（配错歌比没有更糟）。
    if (query.artist.trim().isEmpty) {
      candidates = [
        for (final c in candidates)
          if (_sameTitle(c.trackName, title) &&
              durSec > 0 &&
              c.duration > 0 &&
              (c.duration - durSec).abs() <= 5)
            c,
      ];
      if (candidates.isEmpty) return null;
    }

    // 纯音乐守卫：曲名 + 歌手 + 时长都吻合的候选被标记为纯音乐，且没有同样吻合的带词版本时，
    // 认定这首歌是纯音乐 —— 不配任何歌词（宁可没有，也不给纯音乐硬配同名歌曲的词）。
    if (_isInstrumental(candidates, query)) return null;

    final wantHant = wantsTraditional(query);
    for (final c in candidates) {
      c.rejected = c.lines.isNotEmpty && TranslationFilter.isRejected(c, title);
    }
    final target = decideSongLang(candidates, query);

    LrclibCandidate? best, alt;
    var bestScore = double.negativeInfinity, altScore = double.negativeInfinity;
    for (final c in candidates) {
      if (c.lines.isEmpty) continue;
      final score =
          _score(c, target, title, durSec, wantHant) +
          (_sameArtist(c, query) ? 15 : 0);
      if (c.rejected) {
        if (score - 40 > altScore) {
          altScore = score - 40;
          alt = c;
        }
      } else if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    // 全部被翻译规则淘汰时退而求其次：有词总比没词好
    final pick = best ?? alt;
    if (pick == null) return null;

    // 简繁字形对齐：要简体但库里只有繁体（或反之）时逐字转换，不改动文种
    var synced = pick.synced;
    if (target == LyricLang.zh) {
      final t = ZhScript.countTraditional(synced),
          s = ZhScript.countSimplified(synced);
      if (!wantHant && t >= 3 && t > s) {
        synced = ZhScript.convert(synced, toSimplified: true);
      } else if (wantHant && s >= 3 && s > t) {
        synced = ZhScript.convert(synced, toSimplified: false);
      }
    }
    return LrclibSelection(synced, target);
  }

  /// 歌曲语言：候选歌词按语言投票（曲名一致、时长吻合的票更重），曲名 / 歌手文本各投一张小票。
  static LyricLang decideSongLang(
    List<LrclibCandidate> candidates,
    LyricsQuery query,
  ) {
    final votes = <LyricLang, double>{};
    void vote(LyricLang lang, double w) {
      if (lang == LyricLang.unknown) return;
      votes[lang] = (votes[lang] ?? 0) + w;
    }

    final durSec = query.durationMs / 1000;
    for (final c in candidates) {
      if (c.lines.isEmpty || c.rejected || _otherArtist(c, query)) continue;
      var w = 1.0;
      if (_sameTitle(c.trackName, query.title)) w += 1;
      if (_sameArtist(c, query)) w += 1;
      if (durSec > 0 && c.duration > 0) {
        final dd = (c.duration - durSec).abs();
        if (dd <= 3) {
          w += 1;
        } else if (dd > 20) {
          w *= 0.3; // 时长差太多多半是别的歌 / 别的版本
        }
      }
      vote(lyricLang(c.originalText), w);
    }
    vote(detectLang(query.title), 1.5);
    vote(detectLang(query.artist), 0.5);

    var best = LyricLang.unknown;
    var bestV = 0.0;
    votes.forEach((lang, v) {
      if (v > bestV) {
        bestV = v;
        best = lang;
      }
    });
    return best;
  }

  static double _score(
    LrclibCandidate c,
    LyricLang target,
    String title,
    double durSec,
    bool wantHant,
  ) {
    var score = langScore(target, c.originalText);
    if (target == LyricLang.zh) {
      final t = ZhScript.countTraditional(c.originalText),
          s = ZhScript.countSimplified(c.originalText);
      if (t >= 3 || s >= 3) score += (t > s) == wantHant ? 10 : -25;
    }
    if (_sameTitle(c.trackName, title)) score += 12;
    if (durSec > 0 && c.duration > 0) {
      final dd = (c.duration - durSec).abs();
      if (dd <= 3) {
        score += 10;
      } else if (dd <= 8) {
        score += 4;
      } else if (dd > 20) {
        score -= 15;
      }
    }
    return score;
  }

  /// 判定当前曲目是纯音乐：存在「精确吻合」（曲名一致、歌手对上、时长差 ≤ 5 秒）的纯音乐候选，
  /// 且没有同样精确吻合的带词候选（同一首歌常在库里同时有两种记录，带词的优先）。
  static bool _isInstrumental(
    List<LrclibCandidate> candidates,
    LyricsQuery query,
  ) {
    final durSec = query.durationMs / 1000;
    bool exact(LrclibCandidate c) =>
        _sameTitle(c.trackName, query.title) &&
        _sameArtist(c, query) &&
        (durSec <= 0 || c.duration <= 0 || (c.duration - durSec).abs() <= 5);
    var instrumentalExact = false;
    for (final c in candidates) {
      if (!exact(c)) continue;
      if (c.instrumental) {
        instrumentalExact = true;
      } else if (c.lines.isNotEmpty) {
        return false; // 有精确吻合的带词版本：不是纯音乐
      }
    }
    return instrumentalExact;
  }

  static bool _sameArtist(LrclibCandidate c, LyricsQuery query) =>
      ArtistMatcher.compare(query.artist, c.artistName) == ArtistMatch.match;

  static bool _sameTitle(String a, String b) =>
      LyricsTitle.search(a).toLowerCase() ==
      LyricsTitle.search(b).toLowerCase();
}
