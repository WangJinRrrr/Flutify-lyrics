import 'package:flutify_app/models/album.dart';
import 'package:flutify_app/models/artist.dart';
import 'package:flutify_app/models/image.dart';
import 'package:flutify_app/models/playlist.dart';
import 'package:flutify_app/models/track.dart';

/// 测试专用的合成曲库：全部是虚构数据，不含任何真实账号 / 探测输出。
///
/// 只用于 `test/` 下的单元测试；App 本身不再携带任何示例数据。
class SampleCatalog {
  SampleCatalog._();

  static const SpotifyArtist artistA = SpotifyArtist(
    id: 'artistA000000000000001',
    name: 'Artist A',
    uri: 'spotify:artist:artistA000000000000001',
  );

  static const SpotifyArtist artistB = SpotifyArtist(
    id: 'artistB000000000000002',
    name: 'Artist B',
    uri: 'spotify:artist:artistB000000000000002',
  );

  static const SpotifyAlbum albumA = SpotifyAlbum(
    id: 'albumA0000000000000001',
    name: 'Album A',
    uri: 'spotify:album:albumA0000000000000001',
    totalTracks: 2,
    images: [SpotifyImage(url: 'https://example.test/cover-a.jpg')],
    artists: [artistA],
  );

  static const SpotifyTrack track1 = SpotifyTrack(
    id: 'track10000000000000001',
    name: 'Track One',
    uri: 'spotify:track:track10000000000000001',
    artists: [artistA],
    album: albumA,
    durationMs: 180000,
  );

  static const SpotifyTrack track2 = SpotifyTrack(
    id: 'track20000000000000002',
    name: 'Track Two',
    uri: 'spotify:track:track20000000000000002',
    artists: [artistA, artistB],
    album: albumA,
    durationMs: 200000,
  );

  static const SpotifyTrack track3 = SpotifyTrack(
    id: 'track30000000000000003',
    name: 'Track Three',
    uri: 'spotify:track:track30000000000000003',
    artists: [artistB],
    durationMs: 210000,
  );

  static const SpotifyTrack track4 = SpotifyTrack(
    id: 'track40000000000000004',
    name: 'Track Four',
    uri: 'spotify:track:track40000000000000004',
    artists: [artistB],
    durationMs: 190000,
  );

  /// 账号歌单（模拟 rootlist 返回的远端歌单）。
  static const SpotifyPlaylist remotePlaylist = SpotifyPlaylist(
    id: 'playlist00000000000001',
    name: 'Remote Mix',
    uri: 'spotify:playlist:playlist00000000000001',
    ownerName: 'Spotify',
    totalTracks: 12,
  );
}
