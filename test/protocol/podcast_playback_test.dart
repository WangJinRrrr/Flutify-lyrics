import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/services/protocol/eme_track_audio_source.dart';
import 'package:flutify_app/services/protocol/track_playback_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const id = '0123456789012345678901';
const uri = 'spotify:episode:$id';
http.Response manifest() => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'media': {
        uri: {
          'item': {
            'metadata': {'name': '你好・音楽 🎵', 'duration': 3600000},
            'manifest': {
              'file_urls_external': [
                {'file_url': 'https://podcast.example/audio'},
              ],
            },
          },
        },
      },
    }),
  ),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'episode manifest retains type and correctly decodes non-ASCII metadata',
    () async {
      final media = await fetchTrackPlaybackMedia(
        'https://open.spotify.com/episode/$id?si=abc',
        headers: () async => {},
        client: MockClient((request) async {
          expect(request.url.path, endsWith(uri));
          expect(
            request.url.queryParametersAll['manifestFileFormat'],
            contains('file_urls_external'),
          );
          return manifest();
        }),
      );
      expect(media.name, '你好・音楽 🎵');
      expect(media.durationMs, 3600000);
      expect(media.externalUrls.single, 'https://podcast.example/audio');
    },
  );

  test(
    'production source streams full episode without Web DRM login or whole-file buffering',
    () async {
      final dir = await Directory.systemTemp.createTemp('flutify-podcast-');
      addTearDown(() => dir.delete(recursive: true));
      final requests = <http.Request>[];
      final source = EmeTrackAudioSource(
        accessToken: () async => 'test',
        cacheDirectory: dir.path,
        webSessionReady: () => false,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.host != 'podcast.example') return manifest();
          expect(request.headers.containsKey('authorization'), isFalse);
          final range = (request.headers['Range'] ?? request.headers['range'])!
              .substring(6)
              .split('-')
              .map(int.parse)
              .toList();
          return http.Response.bytes(
            [for (var i = range[0]; i <= range[1]; i++) i],
            206,
            headers: {
              'content-type': 'audio/mpeg',
              'content-range': 'bytes ${range[0]}-${range[1]}/10',
            },
          );
        }),
      );
      addTearDown(source.dispose);
      final audio = await source.open(uri);
      expect(audio.emeContent, isNull);
      expect(audio.stream, isNotNull);
      expect(audio.file.existsSync(), isFalse);
      expect(audio.playbackInfo.format, 'file_urls_external');
      expect(await audio.stream!.read(7, 10).expand((b) => b).toList(), [
        7,
        8,
        9,
      ]);
      final before = requests.length;
      await source.prefetch(uri);
      expect(requests.length, before);
      final saved = await source.load(uri);
      expect(await saved.file.readAsBytes(), List.generate(10, (i) => i));
      expect(File('${saved.path}.part').existsSync(), isFalse);
    },
  );

  test('failed full download removes partial podcast cache', () async {
    final dir = await Directory.systemTemp.createTemp(
      'flutify-podcast-failure-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final source = EmeTrackAudioSource(
      accessToken: () async => 'test',
      cacheDirectory: dir.path,
      client: MockClient((r) async {
        if (r.url.host != 'podcast.example') return manifest();
        return http.Response.bytes(
          [0],
          206,
          headers: {
            'content-type': 'audio/mpeg',
            'content-range': 'bytes 0-0/10',
          },
        );
      }),
    );
    addTearDown(source.dispose);
    await expectLater(source.load(uri), throwsA(isA<Exception>()));
    expect(
      await dir.list(recursive: true).where((e) => e is File).toList(),
      isEmpty,
    );
  });
}
