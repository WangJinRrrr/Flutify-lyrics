import 'dart:convert';

import 'package:flutify_app/models/image.dart';
import 'package:flutify_app/services/library/playlist_cover.dart';
import 'package:flutify_app/services/library/rootlist_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 歌单封面推导：pictureSize → 上传封面 picture（Base64 图片 ID）→ 曲目专辑封面四宫格。
/// 所有 ID 均为合成数据。
void main() {
  // 20 字节合成图片 ID：ab67706c0000bebb + 12 字节递增序列
  final uploadedId = [0xab, 0x67, 0x70, 0x6c, 0x00, 0x00, 0xbe, 0xbb, for (var i = 1; i <= 12; i++) i];
  final uploadedHex = uploadedId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String albumId(int n) => 'ab67616d0000b273${n.toRadixString(16).padLeft(24, '0')}';
  List<SpotifyImage> albumCover(int n) => [
        SpotifyImage(url: 'https://i.scdn.co/image/ab67616d00004851${n.toRadixString(16).padLeft(24, '0')}'),
        SpotifyImage(url: 'https://i.scdn.co/image/${albumId(n)}'),
      ];

  test('pictureSize 优先 large', () {
    final images = PlaylistCover.fromAttributes({
      'pictureSize': [
        {'targetName': 'small', 'url': 'https://example.test/s'},
        {'targetName': 'large', 'url': 'https://example.test/l'},
      ],
      'picture': base64.encode(uploadedId),
    });
    expect(images.single.url, 'https://example.test/l');
  });

  test('只有上传封面 picture：Base64 图片 ID 转 i.scdn.co 地址', () {
    final images = PlaylistCover.fromAttributes({'name': 'x', 'picture': base64.encode(uploadedId)});
    expect(images.single.url, 'https://i.scdn.co/image/$uploadedHex');
  });

  test('picture 损坏或缺失时返回空列表', () {
    expect(PlaylistCover.fromAttributes({'picture': '%%%'}), isEmpty);
    expect(PlaylistCover.fromAttributes({'name': 'x'}), isEmpty);
    expect(PlaylistCover.fromAttributes(null), isEmpty);
  });

  test('≥ 4 张不同专辑封面拼成四宫格（同专辑去重，取 640px 版本）', () {
    final images = PlaylistCover.fromAlbumCovers([albumCover(1), albumCover(1), albumCover(2), albumCover(3), albumCover(4)]);
    expect(images.single.url, 'https://mosaic.scdn.co/640/${albumId(1)}${albumId(2)}${albumId(3)}${albumId(4)}');
  });

  test('不足 4 张不同封面：用第一张', () {
    final images = PlaylistCover.fromAlbumCovers([const [], albumCover(1), albumCover(2)]);
    expect(images.single.url, albumCover(1).first.url);
    expect(PlaylistCover.fromAlbumCovers(const []), isEmpty);
  });

  test('rootlist 解析使用上传封面', () {
    final playlists = RootlistParser.parse({
      'contents': {
        'items': [
          {'uri': 'spotify:playlist:p1'},
          {'uri': 'spotify:playlist:p2'},
        ],
        'metaItems': [
          {
            'attributes': {'name': 'Uploaded', 'picture': base64.encode(uploadedId)},
          },
          {
            'attributes': {'name': 'No cover'},
          },
        ],
      },
    });
    expect(playlists.first.images.single.url, 'https://i.scdn.co/image/$uploadedHex');
    expect(playlists.last.images, isEmpty, reason: '无封面交给数据源拼四宫格');
  });
}
