import 'package:flutify_app/models/home_feed.dart';
import 'package:flutify_app/services/pathfinder/home_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// HomeParser：结构与线上 home 查询一致的合成响应（名称 / ID 均为虚构）。
void main() {
  Map<String, dynamic> label(String text) => {
    'transformedLabel': text,
    'translatedBaseText': text,
  };

  Map<String, dynamic> playlistItem(
    String id, {
    String name = 'P',
    String description = '',
  }) => {
    'uri': 'spotify:playlist:$id',
    'data': null,
    'content': {
      '__typename': 'PlaylistResponseWrapper',
      'data': {
        '__typename': 'Playlist',
        'uri': 'spotify:playlist:$id',
        'name': name,
        'description': description,
        'images': {
          'items': [
            {
              'sources': [
                {
                  'url': 'https://example.invalid/$id.jpg',
                  'width': 640,
                  'height': 640,
                },
              ],
            },
          ],
        },
        'ownerV2': {
          'data': {'__typename': 'User', 'name': 'Owner'},
        },
        'content': {'totalCount': 30},
      },
    },
  };

  Map<String, dynamic> artistEntity(String id, String name) => {
    '__typename': 'ArtistResponseWrapper',
    '_uri': 'spotify:artist:$id',
    'data': {
      '__typename': 'Artist',
      'uri': 'spotify:artist:$id',
      'profile': {'name': name},
      'visuals': {
        'avatarImage': {
          'sources': [
            {
              'url': 'https://example.invalid/$id.jpg',
              'width': 160,
              'height': 160,
            },
          ],
        },
      },
    },
  };

  Map<String, dynamic> section(
    String typename,
    String uri,
    List<Object> items, {
    Map<String, dynamic>? extra,
    int? totalCount,
  }) => {
    'uri': uri,
    'data': {'__typename': typename, ...?extra},
    'sectionItems': {'items': items, 'totalCount': totalCount ?? items.length},
  };

  const liked = {
    'uri': 'spotify:user:@:collection',
    'data': null,
    'content': {
      '__typename': 'UnknownType',
      'uri': 'spotify:user:@:collection',
    },
  };

  Map<String, dynamic> recentsList() => {
    'uri': 'spotify:list:recents',
    'content': {
      '__typename': 'ListResponseWrapper',
      'data': {
        '__typename': 'List',
        'items': {
          'items': [
            {
              'uid': 'u1',
              'entity': {
                '_uri': 'spotify:playlist:r1',
                'data': {
                  'identityTrait': {
                    'name': 'Recent Mix',
                    'description': 'A &amp; B',
                    'contributors': {
                      'items': [
                        {'name': 'Spotify', 'uri': 'spotify:user:spotify'},
                      ],
                    },
                  },
                  'visualIdentityTrait': {
                    'squareCoverImage': {
                      'image': {
                        'data': {
                          'sources': [
                            {
                              'url': 'https://example.invalid/r1.jpg',
                              'maxWidth': 640,
                              'maxHeight': 640,
                            },
                          ],
                        },
                      },
                    },
                  },
                  'entityTypeTrait': {'type': 'ENTITY_TYPE_PLAYLIST'},
                },
              },
            },
            {
              'uid': 'u2',
              'entity': {'_uri': 'spotify:collection:tracks', 'data': {}},
            },
            {
              'uid': 'u3',
              'entity': {
                '_uri': 'spotify:album:r3',
                'data': {
                  'identityTrait': {
                    'name': 'Recent Album',
                    'contributors': {
                      'items': [
                        {'name': 'Artist X', 'uri': 'spotify:artist:x'},
                      ],
                    },
                  },
                },
              },
            },
          ],
        },
      },
    },
  };

  Map<String, dynamic> response() => {
    'home': {
      'greeting': label('早上好'),
      'homeChips': [
        {
          'id': 'music-chip',
          'label': label('音乐'),
          'subChips': [
            {'id': 'sub-a', 'label': label('关注中')},
          ],
        },
        {'id': 'podcasts-chip', 'label': label('播客'), 'subChips': []},
      ],
      'sectionContainer': {
        'sections': {
          'items': [
            // 7 个快捷入口（奇数）→ 去掉最后一个
            section('HomeShortsSectionData', 'spotify:section:shorts', [
              liked,
              for (var i = 0; i < 6; i++) playlistItem('s$i'),
            ]),
            section(
              'HomeGenericSectionData',
              'spotify:section:generic',
              [
                playlistItem(
                  'g1',
                  name: 'Mix',
                  description: '<a href="x">Desc</a>',
                ),
                playlistItem('g2'),
              ],
              extra: {
                'title': label('与 Artist Y 相似'),
                'subtitle': label(''),
                'headerEntity': artistEntity('y', 'Artist Y'),
              },
              totalCount: 25,
            ),
            section(
              'HomeRecentlyPlayedSectionData',
              'spotify:section:recents',
              [recentsList()],
              extra: {'title': label('最近播放')},
            ),
            // 连续的推荐流分区合并为一个；艺人条目不进推荐流
            section(
              'HomeFeedBaselineSectionData',
              'spotify:section:f1',
              [playlistItem('f1')],
              extra: {'title': label('为你推荐'), 'iconName': ''},
            ),
            section(
              'HomeFeedBaselineSectionData',
              'spotify:section:f2',
              [
                {
                  'uri': 'spotify:artist:z',
                  'content': {
                    '__typename': 'ArtistResponseWrapper',
                    'data': artistEntity('z', 'Z')['data'],
                  },
                },
              ],
              extra: {'title': label('ignored')},
            ),
            section(
              'HomeFeedBaselineSectionData',
              'spotify:section:f3',
              [playlistItem('f3')],
              extra: {
                'title': label('与 Artist Y 相似'),
                'headerEntity': artistEntity('y', 'Artist Y'),
              },
            ),
            // 不展示的类型
            section('HomeNativeAdsSectionData', 'spotify:section:ads', [
              playlistItem('ad'),
            ]),
            section(
              'HomeGenericSectionData',
              'spotify:section:podcasts',
              [
                {
                  'uri': 'spotify:show:p1',
                  'content': {
                    '__typename': 'PodcastOrAudiobookResponseWrapper',
                    'data': {
                      '__typename': 'Podcast',
                      'uri': 'spotify:show:p1',
                      'name': 'Show',
                      'publisher': {'name': 'Publisher'},
                      'coverArt': {
                        'sources': [
                          {
                            'url': 'https://example.invalid/p1.jpg',
                            'width': 300,
                            'height': 300,
                          },
                        ],
                      },
                    },
                  },
                },
              ],
              extra: {'title': label('播客')},
            ),
          ],
        },
      },
    },
  };

  test('greeting, chips and shortcuts', () {
    final feed = HomeParser.parse(response());
    expect(feed.greeting, '早上好');
    expect(feed.chips.map((c) => c.id), ['music-chip', 'podcasts-chip']);
    expect(feed.chips.first.subChips.single.label, '关注中');

    expect(feed.shortcuts, hasLength(6), reason: '7 个（奇数）去掉最后一个');
    expect(feed.shortcuts.first.kind, HomeItemKind.likedSongs);
    expect(feed.shortcuts[1].kind, HomeItemKind.playlist);
  });

  test('sections keep server order; feed baseline merges into one grid', () {
    final feed = HomeParser.parse(response());
    expect(feed.sections.map((s) => s.kind), [
      HomeSectionKind.shelf,
      HomeSectionKind.recents,
      HomeSectionKind.feed,
      HomeSectionKind.shelf,
    ]);

    final generic = feed.sections.first;
    expect(generic.title, '与 Artist Y 相似');
    expect(generic.headerArtist?.name, 'Artist Y');
    expect(generic.hasMore, isTrue);
    expect(generic.items.first.subtitle, 'Desc', reason: '描述去掉 HTML');
    expect(generic.items.first.imageUrl, 'https://example.invalid/g1.jpg');

    final feedGrid = feed.sections[2];
    expect(feedGrid.items.map((i) => i.uri), [
      'spotify:playlist:f1',
      'spotify:playlist:f3',
    ]);
    expect(feedGrid.items.first.reason, '为你推荐');
    expect(feedGrid.items.last.reasonArtist?.name, 'Artist Y');

    final podcast = feed.sections.last.items.single;
    expect(podcast.kind, HomeItemKind.podcast);
    expect(podcast.subtitle, 'Publisher');
    expect(podcast.isOpenable, isTrue); // 播客节目页已支持
  });

  test('recently played reads trait-based entities', () {
    final recents = HomeParser.parse(response()).sections[1];
    expect(recents.title, '最近播放');
    expect(recents.items.map((i) => i.kind), [
      HomeItemKind.playlist,
      HomeItemKind.likedSongs,
      HomeItemKind.album,
    ]);

    final mix = recents.items.first;
    expect(mix.title, 'Recent Mix');
    expect(mix.subtitle, 'A & B');
    expect(mix.imageUrl, 'https://example.invalid/r1.jpg');
    expect(mix.playlist?.id, 'r1');

    expect(recents.items.last.album?.artists.single.name, 'Artist X');
    expect(recents.hasMore, isFalse);
  });

  test('section lookup by uri and empty responses', () {
    expect(
      HomeParser.section(response(), 'spotify:section:generic')?.items,
      hasLength(2),
    );
    expect(HomeParser.section(response(), 'spotify:section:missing'), isNull);
    expect(HomeParser.parse({}).isEmpty, isTrue);
    expect(
      HomeParser.isLikedSongsUri('spotify:user:someone:collection'),
      isTrue,
    );
    expect(HomeParser.isLikedSongsUri('spotify:collection:tracks'), isTrue);
    expect(HomeParser.isLikedSongsUri('spotify:user:someone'), isFalse);
  });
}
