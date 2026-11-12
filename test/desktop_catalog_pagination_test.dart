import 'dart:convert';

import 'package:flutify_app/services/pathfinder/desktop_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _track(int id) => {
  'item': {
    '__typename': 'TrackResponseWrapper',
    'data': {'uri': 'spotify:track:$id', 'name': 'Track $id'},
  },
};

Map<String, dynamic> _release(int id) => {
  'releases': {
    'items': [
      {
        'uri': 'spotify:album:$id',
        'name': 'Album $id',
        'date': {'year': 2026},
      },
    ],
  },
};

DesktopDataSource _source(
  Map<String, dynamic> Function(String operation, Map variables) respond,
) => DesktopDataSource(
  MockClient((request) async {
    final body = jsonDecode(request.body) as Map;
    return http.Response(
      jsonEncode({'data': respond(body['operationName'], body['variables'])}),
      200,
    );
  }),
  headers: () async => {},
);

void main() {
  test(
    'desktop search follows raw offsets beyond ten filtered results',
    () async {
      final offsets = <int>[];
      final source = _source((operation, variables) {
        expect(operation, 'searchDesktop');
        final offset = variables['offset'] as int;
        offsets.add(offset);
        return {
          'searchV2': {
            'tracksV2': {
              'totalCount': 23,
              'items': [
                for (var i = offset; i < offset + 10 && i < 23; i++)
                  if (i == 2) {'item': null} else _track(i),
              ],
            },
            'artists': {'totalCount': 0, 'items': []},
            'playlists': {'totalCount': 0, 'items': []},
          },
        };
      });
      final first = await source.searchPage('query', limit: 10);
      expect(first.tracks.items, hasLength(9));
      expect(first.tracks.total, 23);
      expect(first.tracks.nextOffset, 10);
      expect(first.artists.hasMore, isFalse);
      final second = await source.searchPage(
        'query',
        offset: first.tracks.nextOffset!,
        limit: 10,
      );
      final last = await source.searchPage(
        'query',
        offset: second.tracks.nextOffset!,
        limit: 10,
      );
      expect(offsets, [0, 10, 20]);
      expect(last.tracks.items.last.id, '22');
      expect(last.tracks.hasMore, isFalse);
    },
  );

  test('metadata keeps short and fully filtered pages traversable', () async {
    final source = _source(
      (_, variables) => {
        'searchV2': {
          'tracksV2': {
            'totalCount': 6,
            'items': [null, null],
            'pagingInfo': {'nextOffset': 4},
          },
          'artists': {'totalCount': 0, 'items': []},
          'playlists': {'totalCount': 0, 'items': []},
        },
      },
    );
    final page = await source.searchPage('query', limit: 20);
    expect(page.tracks.items, isEmpty);
    expect(page.tracks.nextOffset, 4);
    expect(page.tracks.hasMore, isTrue);
  });

  test('discography follows pages beyond twenty raw releases', () async {
    final offsets = <int>[];
    final source = _source((operation, variables) {
      if (operation == 'queryArtistOverview') {
        return {
          'artistUnion': {
            'uri': 'spotify:artist:artist',
            'profile': {'name': 'Artist'},
          },
        };
      }
      expect(operation, 'queryArtistDiscographyAll');
      final offset = variables['offset'] as int;
      offsets.add(offset);
      return {
        'artistUnion': {
          'discography': {
            'all': {
              'totalCount': 25,
              'items': [
                for (var i = offset; i < offset + 20 && i < 25; i++)
                  if (i == 3)
                    {
                      'releases': {'items': []},
                    }
                  else
                    _release(i),
              ],
            },
          },
        },
      };
    });
    final first = await source.artistAlbumsPage('artist');
    expect(first.items, hasLength(19));
    expect(first.nextOffset, 20);
    final last = await source.artistAlbumsPage(
      'artist',
      offset: first.nextOffset!,
    );
    expect(offsets, [0, 20]);
    expect(last.items.last.id, '24');
    expect(last.items.last.artists.single.name, 'Artist');
    expect(last.hasMore, isFalse);
  });

  test(
    'album tracks continue beyond fifty with album artwork and year',
    () async {
      final source = _source((operation, variables) {
        expect(operation, 'getAlbum');
        final offset = variables['offset'] as int;
        return {
          'albumUnion': {
            'uri': 'spotify:album:album',
            'name': 'Large album',
            'date': {'year': 2024},
            'coverArt': {
              'sources': [
                {'url': 'https://example.test/cover.jpg'},
              ],
            },
            'tracksV2': {
              'totalCount': 53,
              'items': [
                for (var i = offset; i < offset + 50 && i < 53; i++)
                  {
                    'track': {'uri': 'spotify:track:$i'},
                  },
              ],
            },
          },
        };
      });
      final first = await source.albumTracksPage('album');
      final last = await source.albumTracksPage(
        'album',
        offset: first.nextOffset!,
      );
      expect(first.items, hasLength(50));
      expect(last.items, hasLength(3));
      expect(last.items.last.album?.releaseYear, '2024');
      expect(last.items.last.coverUrl, 'https://example.test/cover.jpg');
      expect(last.hasMore, isFalse);
    },
  );

  test('broken response is an error, not a successful empty search', () async {
    final source = _source((_, _) => {});
    await expectLater(source.searchPage('query'), throwsFormatException);
  });

  test('malformed cached album page is fetched again when retried', () async {
    var attempts = 0;
    final source = _source((_, _) {
      attempts++;
      return {
        'albumUnion': {
          'uri': 'spotify:album:album',
          if (attempts > 1)
            'tracksV2': {
              'items': [_track(1)],
              'totalCount': 1,
            },
        },
      };
    });
    await expectLater(source.albumTracksPage('album'), throwsFormatException);
    final retried = await source.albumTracksPage('album');
    expect(attempts, 2);
    expect(retried.items.single.id, '1');
    expect(retried.hasMore, isFalse);
  });

  test(
    'a non-advancing cursor fails instead of repeatedly fetching a page',
    () async {
      final source = _source(
        (_, _) => {
          'searchV2': {
            'tracksV2': {
              'totalCount': 10,
              'items': [_track(3)],
              'pagingInfo': {'nextOffset': 3},
            },
            'artists': {'items': []},
            'playlists': {'items': []},
          },
        },
      );
      await expectLater(
        source.searchPage('query', offset: 3),
        throwsFormatException,
      );
    },
  );
}
