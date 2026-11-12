import 'artist.dart';
import 'image.dart';

class SpotifyAlbum {
  final String id;
  final String name;
  final String uri;
  final String albumType;
  final String releaseDate;
  final int totalTracks;
  final List<SpotifyImage> images;
  final List<SpotifyArtist> artists;

  const SpotifyAlbum({
    required this.id,
    required this.name,
    this.uri = '',
    this.albumType = 'album',
    this.releaseDate = '',
    this.totalTracks = 0,
    this.images = const [],
    this.artists = const [],
  });

  String get coverUrl => images.isNotEmpty ? images.first.url : '';
  String get artistNames => artists.map((a) => a.name).join(', ');

  /// 播放上下文 URI（uri 缺失时按 id 拼接）。
  String get contextUri => uri.isNotEmpty ? uri : 'spotify:album:$id';

  /// 发行年份，如 "2020"。
  String get releaseYear => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : releaseDate;

  factory SpotifyAlbum.fromJson(Map<String, dynamic> json) {
    return SpotifyAlbum(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      uri: json['uri'] as String? ?? (json['id'] != null ? 'spotify:album:${json['id']}' : ''),
      albumType: json['album_type'] as String? ?? 'album',
      releaseDate: json['release_date'] as String? ?? '',
      totalTracks: json['total_tracks'] as int? ?? 0,
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => SpotifyImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      artists: (json['artists'] as List<dynamic>?)
              ?.map((e) => SpotifyArtist.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'album_type': albumType,
    'release_date': releaseDate,
    'total_tracks': totalTracks,
    'images': images.map((e) => e.toJson()).toList(),
    'artists': artists.map((e) => e.toJson()).toList(),
  };
}
