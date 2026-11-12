import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'lrc_parser.dart';
import 'lyric_script.dart';
import 'lyrics_language.dart';
import 'netease_translation_source.dart';
import 'translation_merge.dart';

/// 社区来源（QQ 音乐 / 网易云）自带的同步歌词查询结果：[lyrics] 为 null 表示没找到；
/// [networkError] 表示没找到可能只是网络问题，调用方不缓存本次结果。
class SourceLyricsLookup {
  final SpotifyLyrics? lyrics;
  final bool networkError;

  const SourceLyricsLookup(this.lyrics, {this.networkError = false});
}

/// 既能给译文、也能给原文（带译文）的来源。
abstract interface class OriginalLyricsSource {
  Future<SourceLyricsLookup> findLyrics(LyricsQuery query);
}

/// 把 LRC 原文与 tlyric 译文拼成一份带译文的同步歌词。
class CommunityLyrics {
  CommunityLyrics._();

  static final RegExp _credit = RegExp(
    r'^\s*(作词|作曲|编曲|制作人?|词|曲|混音|母带|录音|监制|和声|Lyrics?|Composer|Arranger|Producer|Written by)\s*[:：]',
    caseSensitive: false,
  );

  /// 至少要有这么多非空行才当作歌词（过滤「纯音乐，请欣赏」之类）。
  static const int minLines = 4;

  static SpotifyLyrics? build(
    String lrc,
    String tlyric,
    LyricsProvider provider,
  ) {
    final lines = [
      for (final line in LrcParser.parse(lrc))
        if (!(line.startTimeMs <= 30000 && _credit.hasMatch(line.words))) line,
    ];
    if (lines.where((l) => l.words.trim().isNotEmpty).length < minLines) {
      return null;
    }
    final text = TranslationMerge.originalText(lines);
    final lang = lyricLang(text);
    List<LyricLine>? translated;
    if (tlyric.trim().isNotEmpty && lang != LyricLang.zh) {
      translated = NeteaseTranslationSource.align(lrc, tlyric, lines);
      if (translated != null &&
          !LyricsLanguage.of(
            'und',
            translated.map((l) => l.words).join('\n'),
          ).startsWith('zh')) {
        translated = null;
      }
    }
    return SpotifyLyrics(
      provider: provider,
      translationProvider: translated == null ? null : provider,
      language: switch (lang) {
        LyricLang.zh => 'zh',
        LyricLang.ja => 'ja',
        LyricLang.ko => 'ko',
        _ => 'und',
      },
      lines: [
        for (final (i, l) in lines.indexed)
          LyricLine(
            startTimeMs: l.startTimeMs,
            words: l.words,
            translation: translated?[i].words ?? '',
          ),
      ],
    );
  }
}