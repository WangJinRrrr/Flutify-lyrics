import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/eme/fairplay.dart';
import 'package:flutify_app/services/eme/streaming_download.dart';
import 'package:flutify_app/services/protocol/eme_track_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late EmeTrackAudioSource source;
  String? playing;
  const id = '0000000000000000000001';
  const fileId = '1111111111111111111111111111111111111111';
  setUp(() async {
    debugUseFairPlayOverride = false;
    root = await Directory.systemTemp.createTemp('flutify-audio-trim-');
    playing = null;
    source = EmeTrackAudioSource(
      cacheDirectory: root.path,
      accessToken: () async => 'test',
      playingPath: () => playing,
      client: MockClient((request) async {
        if (request.url.path.contains('track-playback')) {
          return http.Response(
            jsonEncode({
              'media': {
                'spotify:track:$id': {
                  'item': {
                    'metadata': {'duration': 1000},
                    'manifest': {
                      'file_ids_mp4_cbcs': [
                        {
                          'file_id': '2222222222222222222222222222222222222222',
                          'format': 10,
                          'bitrate': 96000,
                        },
                      ],
                      'file_ids_mp4': [
                        {'file_id': fileId, 'format': 10, 'bitrate': 128000},
                      ],
                    },
                  },
                },
              },
            }),
            200,
          );
        }
        if (request.url.path.contains('sneaktables')) {
          // The HLS manifest must match the CENC file even with CBCS first.
          expect(request.url.path, contains(fileId));
          return http.Response('#EXTM3U', 200);
        }
        if (request.url.path.contains('storage-resolve')) {
          expect(request.url.path, contains(fileId));
          return http.Response.bytes(
            (ProtoWriter()..string(2, 'https://cdn.test/audio')).toBytes(),
            200,
          );
        }
        return http.Response.bytes(List.filled(8, 1), 200);
      }),
    );
  });
  tearDown(() async {
    debugUseFairPlayOverride = null;
    source.dispose();
    await root.delete(recursive: true);
  });
  Future<File> seed(String name, int bytes, int ageDays) async {
    final file = File(p.join(root.path, 'eme_audio', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 1));
    await file.setLastModified(
      DateTime.now().subtract(Duration(days: ageDays)),
    );
    return file;
  }

  test(
    'download completion enforces the limit without reopening settings',
    () async {
      final oldest = await seed('old.m4a', 8, 2);
      final recent = await seed('recent.m4a', 4, 1);
      source.maxCacheBytes = 13;
      await source.trimCache();
      expect(await oldest.exists(), true);
      await source.load(id).timeout(const Duration(seconds: 5));
      // No sizeBytes() or setting change: those would mask a missing download hook.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (await oldest.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await oldest.exists(), false);
      expect(await recent.exists(), true);
      expect(
        await File(p.join(root.path, 'eme_audio', '$fileId.m4a.done')).exists(),
        true,
      );
    },
  );

  test(
    'current and downloading audio survive while unused files are evicted',
    () async {
      final active = await seed('playing.m4a', 8, 3);
      final download = await seed('download.m4a', 8, 2);
      final stale = await seed('unused.m4a', 8, 1);
      playing = active.path;
      StreamingDownloads.begin(download.path);
      try {
        source.maxCacheBytes = 8;
        await source.trimCache();
        expect(await active.exists(), true);
        expect(await download.exists(), true);
        expect(await stale.exists(), false);
        StreamingDownloads.end(download.path);
        await source.trimCache();
        expect(await download.exists(), false);
        expect(await active.exists(), true);
      } finally {
        StreamingDownloads.end(download.path);
      }
    },
  );

  test(
    'cache hits update recency and incomplete orphan files count toward the limit',
    () async {
      final hit = await seed('$fileId.m4a', 8, 3);
      await seed('$fileId.m4a.done', 1, 3);
      final orphan = await seed('abandoned.part', 16, 2);
      await source.load(id);
      expect(
        (await hit.lastModified()).isAfter(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        true,
      );
      source.maxCacheBytes = 9;
      await source.trimCache();
      expect(await orphan.exists(), false);
      expect(await hit.exists(), true);
    },
  );
}
