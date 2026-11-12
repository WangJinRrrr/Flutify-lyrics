import 'package:flutify_app/models/home_feed.dart';
import 'package:flutify_app/services/pathfinder/home_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// HomeParser.browseSections：分类页（browsePage）响应 → 分区列表。
///
/// 与 home 同源的分区 / 条目结构（合成响应，名称 / ID 均为虚构）。
void main() {
  Map<String, dynamic> label(String text) => {
    'transformedLabel': text,
    'translatedBaseText': text,
  };

  Map<String, dynamic> playlistItem(String id, {String name = 'P'}) => {
    'uri': 'spotify:playlist:$id',
    'data': null,
    'content': {
      '__typename': 'PlaylistResponseWrapper',
      'data': {
        '__typename': 'Playlist',
        'uri': 'spotify:playlist:$id',
        'name': name,
        'description': '',
        'images': {
          'items': [
            {
              'sources': [
                {'url': 'https://example.invalid/$id.jpg', 'width': 640, 'height': 640},
              ],
            },
          ],
        },
        'ownerV2': {
          'data': {'__typename': 'User', 'name': 'Owner'},
        },
        'content': {'totalCount': 10},
      },
    },
  };

  Map<String, dynamic> section(String uri, String title, List<Object> items) => {
    'uri': uri,
    'data': {'__typename': 'BrowseGenericSectionData', 'title': label(title), 'subtitle': label('')},
    'sectionItems': {'items': items, 'totalCount': items.length},
  };

  test('browse 根字段：分区标题与条目都解析出来', () {
    final data = {
      'browse': {
        'uri': 'spotify:page:mood',
        'sections': {
          'items': [
            section('spotify:section:mood-1', '热门歌单', [playlistItem('p1', name: '歌单一'), playlistItem('p2')]),
            section('spotify:section:mood-2', '为你推荐', [playlistItem('p3')]),
          ],
        },
      },
    };
    final sections = HomeParser.browseSections(data);
    expect(sections, hasLength(2));
    expect(sections[0].title, '热门歌单');
    expect(sections[0].items.map((i) => i.title), ['歌单一', 'P']);
    expect(sections[0].kind, HomeSectionKind.shelf);
    expect(sections[0].totalCount, 2);
    expect(sections[1].title, '为你推荐');
  });

  test('根字段写作 browsePage 也能解析', () {
    final data = {
      'browsePage': {
        'sections': {
          'items': [
            section('spotify:section:s', '标题', [playlistItem('p1')]),
          ],
        },
      },
    };
    expect(HomeParser.browseSections(data), hasLength(1));
  });

  test('条目全部解析不出时跳过该分区；根字段对不上时兜底找 sections', () {
    final data = {
      'data': {
        'unknownRoot': {
          'sections': {
            'items': [
              section('spotify:section:empty', '空分区', [
                {'uri': 'spotify:unknown:x', 'content': null},
              ]),
              section('spotify:section:ok', '正常', [playlistItem('p1')]),
            ],
          },
        },
      },
    };
    final sections = HomeParser.browseSections(data);
    expect(sections, hasLength(1));
    expect(sections[0].title, '正常');
  });

  test('空响应返回空列表而不是抛错', () {
    expect(HomeParser.browseSections(const {}), isEmpty);
    expect(HomeParser.browseSections({'browse': null}), isEmpty);
    expect(HomeParser.browseSections({
      'browse': {
        'sections': {'items': []},
      },
    }), isEmpty);
  });
}
