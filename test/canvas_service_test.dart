import 'dart:async';
import 'dart:convert';

import 'package:flutify_app/services/canvas/canvas_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const uri = 'spotify:track:0123456789012345678901';
Map<String, dynamic> data({
  String type = 'VIDEO',
  String? url = 'https://cdn.example/canvas.mp4',
}) => {
  'trackUnion': {
    '__typename': 'Track',
    'canvas': {'type': type, 'url': url, 'fileId': 'manifest-only'},
  },
};

void main() {
  test(
    'uses Canvas query, coalesces requests and never sends account headers to CDN',
    () async {
      final gate = Completer<void>();
      var queries = 0;
      var downloads = 0;
      final service = CanvasService(
        MockClient((request) async {
          if (request.method == 'POST') {
            queries++;
            final body = jsonDecode(request.body);
            expect(body['operationName'], 'canvas');
            expect(body['variables'], {'trackUri': uri});
            expect(
              body['extensions']['persistedQuery']['sha256Hash'],
              '575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f',
            );
            await gate.future;
            return http.Response(jsonEncode({'data': data()}), 200);
          }
          downloads++;
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('client-token'), isFalse);
          return http.Response.bytes([1, 2, 3], 200);
        }),
        headers: () async => {'authorization': 'Bearer test'},
      );
      final a = service.get(uri);
      final b = service.get(uri);
      gate.complete();
      expect((await a)!.bytes, [1, 2, 3]);
      expect(identical(await b, await service.get(uri)), isTrue);
      expect(queries, 1);
      expect(downloads, 1);
    },
  );

  test(
    'unsupported URI, missing Canvas, insecure or manifest-only URL fall back',
    () async {
      var queries = 0;
      final service = CanvasService(
        MockClient((_) async {
          queries++;
          return http.Response(
            jsonEncode({
              'data': {
                'trackUnion': {'__typename': 'Track'},
              },
            }),
            200,
          );
        }),
        headers: () async => {},
      );
      expect(
        await service.get('spotify:episode:0123456789012345678901'),
        isNull,
      );
      expect(queries, 0);
      expect(await service.get(uri), isNull);
      expect(await service.get(uri), isNull);
      expect(queries, 1);
      expect(SpotifyCanvas.fromData(data(url: null)), isNull);
      expect(SpotifyCanvas.fromData(data(url: 'http://cdn.example/x')), isNull);
      expect(SpotifyCanvas.fromData(data(type: 'UNKNOWN')), isNull);
      expect(SpotifyCanvas.fromData(data(type: 'GIF'))!.isVideo, isFalse);
    },
  );

  test('oversized media and upstream failure do not affect playback', () async {
    final service = CanvasService(
      MockClient(
        (request) async => request.method == 'POST'
            ? http.Response(jsonEncode({'data': data()}), 200)
            : http.Response.bytes(List.filled(12 * 1024 * 1024 + 1, 0), 200),
      ),
      headers: () async => {},
    );
    expect(await service.get(uri), isNull);
    final failing = CanvasService(
      MockClient((_) async => http.Response('offline', 503)),
      headers: () async => {},
    );
    expect(await failing.get(uri), isNull);
  });
}
