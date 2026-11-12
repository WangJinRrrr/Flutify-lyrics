import 'image.dart';

class SpotifyArtist {
  final String id;
  final String name;
  final String uri;
  final List<SpotifyImage> images;
  final List<String> genres;
  final int? followers;
  final int? popularity;

  const SpotifyArtist({
    required this.id,
    required this.name,
    this.uri = '',
    this.images = const [],
    this.genres = const [],
    this.followers,
    this.popularity,
  });

  String get avatarUrl => images.isNotEmpty ? images.first.url : '';

  /// 播放上下文 URI（uri 缺失时按 id 拼接）。
  String get contextUri => uri.isNotEmpty ? uri : 'spotify:artist:$id';

  factory SpotifyArtist.fromJson(Map<String, dynamic> json) {
    return SpotifyArtist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      uri: json['uri'] as String? ?? (json['id'] != null ? 'spotify:artist:${json['id']}' : ''),
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => SpotifyImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      followers: json['followers'] is Map<String, dynamic>
          ? (json['followers']['total'] as int?)
          : (json['followers'] as int?),
      popularity: json['popularity'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'images': images.map((e) => e.toJson()).toList(),
    'genres': genres,
    'followers': {'total': followers},
    'popularity': popularity,
  };
}
