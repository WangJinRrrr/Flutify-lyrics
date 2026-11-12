import 'album.dart';
import 'artist.dart';
import 'playlist.dart';
import 'track.dart';

/// One server page. Offsets count raw entries, including unavailable entries
/// filtered during parsing; an empty [items] list is not necessarily the end.
class CatalogPage<T> {
  final List<T> items;
  final int offset;
  final int? total;
  final int? nextOffset;

  const CatalogPage({
    required this.items,
    this.offset = 0,
    this.total,
    this.nextOffset,
  });

  /// Derives continuation from raw server entries, never from parsed/deduped
  /// items. Known totals and cursors take precedence over short-page guessing.
  factory CatalogPage.fromSlice({
    required List<T> items,
    required int offset,
    required int limit,
    required int rawCount,
    int? total,
    int? nextOffset,
    bool? hasNextPage,
  }) {
    final more =
        hasNextPage ??
        (nextOffset != null ||
            (total != null ? offset + rawCount < total : rawCount >= limit));
    final next = more ? (nextOffset ?? offset + rawCount) : null;
    if (next != null && next <= offset) {
      throw const FormatException('Catalog page did not advance');
    }
    return CatalogPage(
      items: List.unmodifiable(items),
      offset: offset,
      total: total,
      nextOffset: next,
    );
  }

  bool get hasMore => nextOffset != null;
}

/// Each search section has its own continuation, independent of other sections.
class SearchPage {
  final CatalogPage<SpotifyTrack> tracks;
  final CatalogPage<SpotifyArtist> artists;
  final CatalogPage<SpotifyPlaylist> playlists;

  const SearchPage({
    this.tracks = const CatalogPage(items: []),
    this.artists = const CatalogPage(items: []),
    this.playlists = const CatalogPage(items: []),
  });
}

/// Opaque to views: pass this unchanged to the next artist-song request.
/// Buffered releases avoid re-fetching discography for each album. The caller
/// keeps the previous cursor on failure, making continuation retryable.
class ArtistTracksCursor {
  final String artistId;
  final List<SpotifyAlbum> pendingAlbums;
  final int? nextAlbumOffset;
  final int trackOffset;

  const ArtistTracksCursor({
    required this.artistId,
    this.pendingAlbums = const [],
    this.nextAlbumOffset = 0,
    this.trackOffset = 0,
  });
}

/// A bounded slice of songs from the artist's available discography.
/// This is not a popularity ranking; views can prepend the overview top tracks.
/// The complete song count is unknown until all releases have been visited.
class ArtistTracksPage {
  final List<SpotifyTrack> items;
  final ArtistTracksCursor? nextCursor;

  const ArtistTracksPage({required this.items, this.nextCursor});

  bool get hasMore => nextCursor != null;
}
