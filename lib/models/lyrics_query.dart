import 'track.dart';

/// 查歌词所需的曲目信息。
///
/// Spotify 官方歌词只要 [trackId]；第三方歌词库（LRCLIB）按曲名 / 歌手 / 专辑 / 时长匹配。
class LyricsQuery {
  final String trackId;
  final String title;

  /// 多位艺人以 ", " 连接（与 [SpotifyTrack.artistNames] 一致）。
  final String artist;
  final String album;
  final int durationMs;

  const LyricsQuery({
    required this.trackId,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
  });

  factory LyricsQuery.fromTrack(SpotifyTrack track) => LyricsQuery(
    trackId: track.id,
    title: track.name,
    artist: track.artistNames,
    album: track.album?.name ?? '',
    durationMs: track.durationMs,
  );

  /// 第一位艺人：LRCLIB 的 artist_name 通常只登记主唱，带上合作者反而匹配不到。
  String get primaryArtist {
    final i = artist.indexOf(', ');
    return i < 0 ? artist : artist.substring(0, i);
  }
}
