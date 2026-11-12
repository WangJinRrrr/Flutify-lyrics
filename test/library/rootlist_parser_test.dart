import 'package:flutify_app/services/library/rootlist_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RootlistParser.parse', () {
    test('解析歌单：名称、所有者、曲目数与封面（优先 large）', () {
      final playlists = RootlistParser.parse({
        'contents': {
          'items': [
            {'uri': 'spotify:playlist:pl1'},
            {'uri': 'spotify:playlist:pl2'},
          ],
          'metaItems': [
            {
              'attributes': {
                'name': 'Road Trip',
                'description': '<a href="x">best</a> songs',
                'pictureSize': [
                  {'targetName': 'small', 'url': 'https://example.test/small.jpg'},
                  {'targetName': 'large', 'url': 'https://example.test/large.jpg'},
                ],
              },
              'length': 42,
              'ownerUsername': 'tester',
            },
            {
              'attributes': {'name': 'No Cover'},
              'length': '7',
              'ownerUsername': 'spotify',
            },
          ],
        },
      });

      expect(playlists.map((p) => p.id), ['pl1', 'pl2']);
      expect(playlists.first.name, 'Road Trip');
      expect(playlists.first.description, 'best songs');
      expect(playlists.first.ownerName, 'tester');
      expect(playlists.first.totalTracks, 42);
      expect(playlists.first.coverUrl, 'https://example.test/large.jpg');
      expect(playlists.last.totalTracks, 7, reason: 'length 也可能是字符串');
      expect(playlists.last.images, isEmpty);
    });

    test('文件夹标记与非歌单条目被跳过，文件夹内歌单按顺序平铺', () {
      final playlists = RootlistParser.parse({
        'contents': {
          'items': [
            {'uri': 'spotify:start-group:abc:Folder'},
            {'uri': 'spotify:playlist:inside'},
            {'uri': 'spotify:end-group:abc'},
            {'uri': 'spotify:playlist:outside'},
          ],
          'metaItems': [
            <String, dynamic>{},
            {
              'attributes': {'name': 'Inside'},
            },
            <String, dynamic>{},
            {
              'attributes': {'name': 'Outside'},
            },
          ],
        },
      });

      expect(playlists.map((p) => p.name), ['Inside', 'Outside']);
    });

    test('metaItems 缺失或长度不足时不抛错（名称留空）', () {
      final playlists = RootlistParser.parse({
        'contents': {
          'items': [
            {'uri': 'spotify:playlist:lonely'},
          ],
        },
      });

      expect(playlists.single.id, 'lonely');
      expect(playlists.single.name, isEmpty);
    });

    test('空响应与结构异常返回空列表', () {
      expect(RootlistParser.parse(const {}), isEmpty);
      expect(RootlistParser.parse({'contents': 'oops'}), isEmpty);
    });
  });
}
