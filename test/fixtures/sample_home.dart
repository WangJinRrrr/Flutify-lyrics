import 'package:flutify_app/models/album.dart';
import 'package:flutify_app/models/artist.dart';
import 'package:flutify_app/models/home_feed.dart';
import 'package:flutify_app/models/playlist.dart';

/// 合成的主页数据（全部为虚构名称，无图片地址，不发网络请求）。
///
/// 刻意包含：超长英文 / 中文标题、带艺人头像的分区、艺人圆形卡、播客条目、
/// 20 张带推荐理由的推荐流卡片，用于布局兜底测试。
class SampleHome {
  SampleHome._();

  static const _artist = SpotifyArtist(id: 'a1', name: 'Synthetic Artist', uri: 'spotify:artist:a1');

  static HomeItem playlist(String id, String title, {String subtitle = 'Synthetic description'}) => HomeItem(
    kind: HomeItemKind.playlist,
    uri: 'spotify:playlist:$id',
    title: title,
    subtitle: subtitle,
    playlist: SpotifyPlaylist(id: id, name: title, uri: 'spotify:playlist:$id', description: subtitle),
  );

  static HomeItem album(String id, String title) => HomeItem(
    kind: HomeItemKind.album,
    uri: 'spotify:album:$id',
    title: title,
    subtitle: 'Synthetic Artist, Another Synthetic Artist',
    album: SpotifyAlbum(id: id, name: title, uri: 'spotify:album:$id', artists: const [_artist]),
  );

  static HomeItem artist(String id, String name) => HomeItem(
    kind: HomeItemKind.artist,
    uri: 'spotify:artist:$id',
    title: name,
    artist: SpotifyArtist(id: id, name: name, uri: 'spotify:artist:$id'),
  );

  static const _longTitle = 'An Extremely Long Synthetic Playlist Title That Should Be Truncated Gracefully';
  static const _longCjk = '一个非常非常长的合成歌单标题用来测试中文换行与截断是否正常显示';

  static final HomeFeed feed = HomeFeed(
    greeting: '早上好',
    chips: const [
      HomeChip(
        id: 'music-chip',
        label: '音乐',
        subChips: [
          HomeChip(id: 'sub-1', label: '关注中'),
          HomeChip(id: 'sub-2', label: '一个比较长的二级标签'),
        ],
      ),
      HomeChip(id: 'podcasts-chip', label: '播客'),
    ],
    shortcuts: [
      const HomeItem(kind: HomeItemKind.likedSongs, uri: 'spotify:user:@:collection', title: ''),
      playlist('s1', _longTitle),
      playlist('s2', _longCjk),
      album('s3', 'Short'),
      artist('s4', 'Synthetic Artist With A Long Name'),
      playlist('s5', 'Mix 5'),
      playlist('s6', 'Mix 6'),
      playlist('s7', 'Mix 7'),
    ],
    sections: [
      HomeSection(
        uri: 'spotify:section:made-for',
        kind: HomeSectionKind.shelf,
        title: '根据 synthetic 的喜好推荐',
        items: [for (var i = 0; i < 10; i++) playlist('m$i', i.isEven ? _longTitle : _longCjk)],
        totalCount: 20,
      ),
      HomeSection(
        uri: 'spotify:section:recents',
        kind: HomeSectionKind.recents,
        title: '最近播放',
        items: [
          const HomeItem(kind: HomeItemKind.likedSongs, uri: 'spotify:user:@:collection', title: ''),
          for (var i = 0; i < 6; i++) album('r$i', 'Recent Album $i'),
        ],
      ),
      HomeSection(
        uri: 'spotify:section:more-like',
        kind: HomeSectionKind.shelf,
        title: '与 Synthetic Artist 相似的更多艺人，这是一个故意写得很长的分区标题',
        subtitle: 'A subtitle that is also intentionally long so it needs to be truncated on narrow screens',
        headerArtist: _artist,
        items: [for (var i = 0; i < 8; i++) artist('ma$i', 'Artist $i')],
        totalCount: 8,
      ),
      HomeSection(
        uri: 'spotify:section:podcasts',
        kind: HomeSectionKind.shelf,
        title: 'Synthetic Podcasts',
        items: [
          for (var i = 0; i < 5; i++)
            HomeItem(kind: HomeItemKind.podcast, uri: 'spotify:show:p$i', title: 'Podcast $i', subtitle: 'Publisher'),
        ],
      ),
      HomeSection(
        uri: 'spotify:section:feed',
        kind: HomeSectionKind.feed,
        title: '',
        items: [
          for (var i = 0; i < 20; i++)
            playlist(
              'f$i',
              i.isEven ? _longTitle : 'Feed $i',
            ).withReason(i % 3 == 0 ? '与 Synthetic Artist 相似的更多艺人内容推荐' : '为你推荐', i % 3 == 0 ? _artist : null),
        ],
      ),
      HomeSection(
        uri: 'spotify:section:after-feed',
        kind: HomeSectionKind.shelf,
        title: 'Today\'s biggest hits',
        items: [for (var i = 0; i < 6; i++) album('h$i', 'Hit $i')],
      ),
    ],
  );
}
