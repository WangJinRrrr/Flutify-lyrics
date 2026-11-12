import 'dart:convert';

import 'package:flutify_app/services/pathfinder/desktop_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'playlist follows short pages and preserves order and duplicate tracks',
    () async {
      final offsets = <int>[];
      final uris = [
        'spotify:track:a',
        'spotify:episode:skip',
        'spotify:track:b',
        'spotify:track:a',
        'spotify:track:c',
      ];
      final source = DesktopDataSource(
        MockClient((request) async {
          if (request.method == 'GET') {
            final offset = int.parse(request.url.queryParameters['from']!);
            offsets.add(offset);
            return http.Response(
              jsonEncode({
                if (offset == 0) 'attributes': {'name': 'Synthetic daylist'},
                'length': uris.length,
                'contents': {
                  'items': [
                    for (final uri in uris.skip(offset).take(2)) {'uri': uri},
                  ],
                },
              }),
              200,
            );
          }
          final body = jsonDecode(request.body) as Map;
          final batch = (body['variables']['uris'] as List).cast<String>();
          // Decoration may return a different order and collapse duplicate URIs.
          return http.Response(
            jsonEncode({
              'data': {
                'tracks': [
                  for (final uri in batch.toSet().toList().reversed)
                    {'uri': uri, 'name': uri.split(':').last},
                ],
              },
            }),
            200,
          );
        }),
        headers: () async => {},
      );
      final playlist = await source.playlist('synthetic');
      expect(offsets, [0, 2, 4]);
      expect(playlist!.tracks.map((t) => t.id), ['a', 'b', 'a', 'c']);
      expect(playlist.name, 'Synthetic daylist');
    },
  );

  test('playlist loads beyond the first 100 entries', () async {
    final offsets = <int>[];
    final source = DesktopDataSource(
      MockClient((request) async {
        if (request.method == 'GET') {
          final offset = int.parse(request.url.queryParameters['from']!);
          offsets.add(offset);
          return http.Response(
            jsonEncode({
              'attributes': {'name': 'Long playlist'},
              'length': 205,
              'contents': {
                'items': [
                  for (var i = offset; i < offset + 100 && i < 205; i++)
                    {'uri': 'spotify:track:$i'},
                ],
              },
            }),
            200,
          );
        }
        final batch = (jsonDecode(request.body)['variables']['uris'] as List)
            .cast<String>();
        return http.Response(
          jsonEncode({
            'data': {
              'tracks': [
                for (final uri in batch) {'uri': uri},
              ],
            },
          }),
          200,
        );
      }),
      headers: () async => {},
    );
    final playlist = await source.playlist('synthetic');
    expect(offsets, [0, 100, 200]);
    expect(playlist!.tracks.length, 205);
    expect(playlist.tracks.last.id, '204');
  });

  test(
    'failed continuation is reported instead of presenting a truncated playlist',
    () async {
      final source = DesktopDataSource(
        MockClient((request) async {
          if (request.url.queryParameters['from'] != '0')
            return http.Response('', 500);
          return http.Response(
            jsonEncode({
              'attributes': {'name': 'Incomplete'},
              'length': 3,
              'contents': {
                'items': [
                  {'uri': 'spotify:track:a'},
                ],
              },
            }),
            200,
          );
        }),
        headers: () async => {},
      );
      await expectLater(source.playlist('synthetic'), throwsStateError);
    },
  );
}
