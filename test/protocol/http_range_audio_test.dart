import 'package:flutify_app/services/protocol/http_range_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'seeks fetch just the requested byte interval, end is exclusive',
    () async {
      final ranges = <String>[];
      final client = MockClient((r) async {
        final range = r.headers['Range'] ?? r.headers['range']!;
        ranges.add(range);
        final bounds = range.substring(6).split('-').map(int.parse).toList();
        return http.Response.bytes(
          [for (var i = bounds[0]; i <= bounds[1]; i++) i],
          206,
          headers: {
            'content-type': 'audio/mpeg',
            'content-range': 'bytes ${bounds[0]}-${bounds[1]}/10',
          },
        );
      });
      final audio = await HttpRangeAudio.open(
        client,
        'https://podcast.example/audio',
      );
      expect(audio.length, 10);
      expect(await audio.read(4, 7).expand((b) => b).toList(), [4, 5, 6]);
      expect(await audio.read(9).expand((b) => b).toList(), [9]);
      expect(ranges, ['bytes=0-0', 'bytes=4-6', 'bytes=9-9']);
    },
  );

  test('server ignoring range still returns correct seek bytes', () async {
    final audio = await HttpRangeAudio.open(
      MockClient(
        (_) async => http.Response.bytes(
          List.generate(10, (i) => i),
          200,
          headers: {'content-type': 'audio/mpeg'},
        ),
      ),
      'https://podcast.example/audio',
    );
    expect(await audio.read(7, 9).expand((b) => b).toList(), [7, 8]);
    await expectLater(audio.read(-1).drain<void>(), throwsRangeError);
  });

  test('rejects HTML, wrong ranges and truncated audio', () async {
    await expectLater(
      HttpRangeAudio.open(
        MockClient(
          (_) async => http.Response(
            '<html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
        'https://podcast.example/audio',
      ),
      throwsFormatException,
    );
    var calls = 0;
    final audio = await HttpRangeAudio.open(
      MockClient((_) async {
        calls++;
        return http.Response.bytes(
          [0],
          206,
          headers: {
            'content-type': 'audio/mpeg',
            'content-range': calls < 3 ? 'bytes 0-0/10' : 'bytes 4-6/10',
          },
        );
      }),
      'https://podcast.example/audio',
    );
    await expectLater(audio.read(4, 7).drain<void>(), throwsFormatException);
    await expectLater(audio.read(4, 7).drain<void>(), throwsStateError);
  });
}
