import 'package:flutify_app/models/artist.dart';
import 'package:flutify_app/models/catalog_page.dart';
import 'package:flutify_app/models/playlist.dart';
import 'package:flutify_app/models/track.dart';

List<SpotifyTrack> tracks(int from, int to) => [
  for (var index = from; index < to; index++)
    SpotifyTrack(id: 'track-$index', name: 'Track $index'),
];

SearchPage page({
  List<SpotifyTrack> tracks = const [],
  int trackOffset = 0,
  int? nextTracks,
  List<SpotifyArtist> artists = const [],
  int? nextArtists,
  List<SpotifyPlaylist> playlists = const [],
  int? nextPlaylists,
}) => SearchPage(
  tracks: CatalogPage(
    items: tracks,
    offset: trackOffset,
    nextOffset: nextTracks,
  ),
  artists: CatalogPage(items: artists, offset: 0, nextOffset: nextArtists),
  playlists: CatalogPage(
    items: playlists,
    offset: 0,
    nextOffset: nextPlaylists,
  ),
);
