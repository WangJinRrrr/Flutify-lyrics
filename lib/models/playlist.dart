import 'image.dart';
import 'track.dart';

class SpotifyPlaylist {
  final String id;
  final String name;
  final String uri;
  final String description;
  final String ownerName;
  final List<SpotifyImage> images;
  final List<SpotifyTrack> tracks;
  final int totalTracks;
  final bool isPublic;
  final String? primaryColor;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    this.uri = '',
    this.description = '',
    this.ownerName = 'Spotify',
    this.images = const [],
    this.tracks = const [],
    this.totalTracks = 0,
    this.isPublic = true,
    this.primaryColor,
  });

  String get coverUrl => images.isNotEmpty ? images.first.url : '';

  /// 播放上下文 URI（uri 缺失时按 id 拼接）。
  String get contextUri => uri.isNotEmpty ? uri : 'spotify:playlist:$id';

  SpotifyPlaylist copyWith({
    String? id,
    String? name,
    String? uri,
    String? description,
    String? ownerName,
    List<SpotifyImage>? images,
    List<SpotifyTrack>? tracks,
    int? totalTracks,
    bool? isPublic,
    String? primaryColor,
  }) {
    return SpotifyPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      description: description ?? this.description,
      ownerName: ownerName ?? this.ownerName,
      images: images ?? this.images,
      tracks: tracks ?? this.tracks,
      totalTracks: totalTracks ?? this.totalTracks,
      isPublic: isPublic ?? this.isPublic,
      primaryColor: primaryColor ?? this.primaryColor,
    );
  }

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    List<SpotifyTrack> parsedTracks = [];
    if (json['tracks'] != null) {
      if (json['tracks'] is Map<String, dynamic> && json['tracks']['items'] is List) {
        for (var item in json['tracks']['items']) {
          if (item is Map<String, dynamic> && item['track'] != null) {
            // 加入时间在条目上而不在曲目上
            parsedTracks.add(
              SpotifyTrack.fromJson(
                item['track'] as Map<String, dynamic>,
              ).copyWith(addedAt: SpotifyTrack.parseAddedAt(item['added_at'])),
            );
          } else if (item is Map<String, dynamic>) {
            parsedTracks.add(SpotifyTrack.fromJson(item));
          }
        }
      } else if (json['tracks'] is List) {
        parsedTracks = (json['tracks'] as List)
            .whereType<Map<String, dynamic>>()
            .map((t) => SpotifyTrack.fromJson(t))
            .toList();
      }
    }

    final total = json['tracks'] is Map<String, dynamic>
        ? (json['tracks']['total'] as int? ?? parsedTracks.length)
        : (json['total_tracks'] as int? ?? parsedTracks.length);

    return SpotifyPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      uri: json['uri'] as String? ?? (json['id'] != null ? 'spotify:playlist:${json['id']}' : ''),
      description: json['description'] as String? ?? '',
      ownerName: json['owner'] is Map<String, dynamic>
          ? (json['owner']['display_name'] as String? ?? 'Spotify')
          : 'Spotify',
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => SpotifyImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tracks: parsedTracks,
      totalTracks: total,
      isPublic: json['public'] as bool? ?? true,
      primaryColor: json['primary_color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'description': description,
    'owner': {'display_name': ownerName},
    'images': images.map((e) => e.toJson()).toList(),
    'tracks': {'total': totalTracks, 'items': tracks.map((t) => {'track': t.toJson()}).toList()},
    'public': isPublic,
    'primary_color': primaryColor,
  };
}
