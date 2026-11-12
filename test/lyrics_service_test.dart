import 'dart:convert';

import 'package:flutify_app/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<int> _body(Object json) => utf8.encode(jsonEncode(json));

void main() {
  group('LyricsService.parse', () {
    test('解析按行同步歌词', () {
      final lyrics = LyricsService.parse(_body({
        'lyrics': {
          'syncType': 'LINE_SYNCED',
          'lines': [
            {'startTimeMs': '1500', 'words': 'hello'},
            {'startTimeMs': '3000', 'words': ''},
            {'startTimeMs': '4500', 'words': 'world'},
          ],
        },
      }));

      expect(lyrics.syncType, 'LINE_SYNCED');
      expect(lyrics.lines.map((l) => l.startTimeMs), [1500, 3000, 4500]);
      expect(lyrics.lines[1].words, isEmpty, reason: '同步歌词中的空行（间奏）需保留');
    });

    test('全部是空行等同于没有歌词', () {
      final lyrics = LyricsService.parse(_body({
        'lyrics': {
          'lines': [
            {'startTimeMs': '0', 'words': ''},
            {'startTimeMs': '1000', 'words': '  '},
          ],
        },
      }));

      expect(lyrics.lines, isEmpty);
    });

    test('未同步歌词保留 syncType', () {
      final lyrics = LyricsService.parse(_body({
        'lyrics': {
          'syncType': 'UNSYNCED',
          'lines': [
            {'startTimeMs': '0', 'words': 'plain text'},
          ],
        },
      }));

      expect(lyrics.syncType, 'UNSYNCED');
      expect(lyrics.lines, hasLength(1));
    });

    test('乱码 / 结构异常返回空歌词，不抛错', () {
      expect(LyricsService.parse(utf8.encode('not json')).lines, isEmpty);
      expect(LyricsService.parse(_body([1, 2, 3])).lines, isEmpty);
      expect(LyricsService.parse(_body({'lyrics': 5})).lines, isEmpty);
    });
  });

  group('LyricsService.fetch', () {
    Future<Map<String, String>> headers() async => {'Authorization': 'Bearer t'};

    test('请求 spclient color-lyrics，并补上 WebPlayer 平台声明', () async {
      late http.Request seen;
      final service = LyricsService(
        MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'lyrics': {'lines': []}}), 200);
        }),
        headers: headers,
      );

      await service.fetch('track123');

      expect(seen.url.path, '/color-lyrics/v2/track/track123');
      expect(seen.headers['app-platform'], 'WebPlayer');
      expect(seen.headers['Authorization'], 'Bearer t');
    });

    test('会话自带桌面端头时沿用，不覆盖', () async {
      late http.Request seen;
      final service = LyricsService(
        MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
        headers: () async => {'app-platform': 'Win32_x86_64', 'Authorization': 'Bearer t'},
      );

      await service.fetch('track123');

      expect(seen.headers['app-platform'], 'Win32_x86_64');
    });

    test('404 = 这首歌没有歌词；其他错误抛 LyricsException', () async {
      final notFound = LyricsService(MockClient((_) async => http.Response('', 404)), headers: headers);
      expect((await notFound.fetch('x')).lines, isEmpty);

      final forbidden = LyricsService(MockClient((_) async => http.Response('', 403)), headers: headers);
      await expectLater(forbidden.fetch('x'), throwsA(isA<LyricsException>()));
    });

    test('网络异常映射为 LyricsException', () async {
      final service = LyricsService(MockClient((_) async => throw Exception('offline')), headers: headers);

      await expectLater(service.fetch('x'), throwsA(isA<LyricsException>()));
    });
  });
}
