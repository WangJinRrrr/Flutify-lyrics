import '../../models/lyrics.dart';
import 'lrc_parser.dart';
import 'translation_merge.dart';

/// LRCLIB 返回的一条歌词记录（`/api/get` 返回单个对象，`/api/search` 返回数组）。
///
/// 只保留带同步歌词（`syncedLyrics`）的记录：纯文本歌词 Spotify 自己就有，补全的意义在于时间轴。
class LrclibCandidate {
  final String trackName;
  final String artistName;
  final String albumName;
  final String synced;

  /// 时长（秒），未知为 0。
  final double duration;
  final bool instrumental;

  /// 解析后的歌词行（纯音乐为空）。
  late final List<LyricLine> lines = instrumental
      ? const []
      : LrcParser.parse(synced);

  /// 双语对照拆分后的歌词行（译文存进 [LyricLine.translation]）；不是对照结构为 null。
  /// 选词器的语言投票 / 打分与最终展示都以拆分结果为准。
  late final List<LyricLine>? mergedLines = lines.isEmpty
      ? null
      : TranslationMerge.tryMerge(lines);

  /// 拆分后所有原文行（没有对照结构时即原始歌词）。语言投票、打分只看原文、不掺译文。
  late final String originalText = TranslationMerge.originalText(
    mergedLines ?? lines,
  );

  /// 被判为翻译版 / 音译 / 整体混排（由选词器写入；双语对照不算，见 [mergedLines]）。
  bool rejected = false;

  LrclibCandidate({
    required this.trackName,
    this.artistName = '',
    this.albumName = '',
    required this.synced,
    this.duration = 0,
    this.instrumental = false,
  });

  /// 解析单条记录；没有同步歌词且不是纯音乐标记、或结构不对时返回 null。
  ///
  /// 纯音乐记录（`instrumental: true`，通常没有歌词字段）也要保留：
  /// 选词器用它判定「这首歌是纯音乐」，避免给纯音乐硬配同名歌曲的歌词。
  static LrclibCandidate? fromJson(Object? json) {
    if (json is! Map) return null;
    final instrumental = json['instrumental'] == true;
    final synced = json['syncedLyrics'];
    if ((synced is! String || synced.isEmpty) && !instrumental) return null;
    String str(String key) => json[key] is String ? json[key] as String : '';
    final duration = json['duration'];
    return LrclibCandidate(
      trackName: str('trackName'),
      artistName: str('artistName'),
      albumName: str('albumName'),
      synced: synced is String ? synced : '',
      duration: duration is num ? duration.toDouble() : 0,
      instrumental: instrumental,
    );
  }

  /// 解析 `/api/get`（对象）或 `/api/search`（数组）的响应。
  static List<LrclibCandidate> listFrom(Object? json) {
    final items = json is List ? json : [json];
    return [for (final item in items) ?fromJson(item)];
  }
}
