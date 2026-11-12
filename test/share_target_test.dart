import 'package:flutify_app/models/share_target.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分享目标：链接 / URI / 嵌入代码的生成规则，以及「无公开链接」的判断。
void main() {
  const id = '4uLU6hMCjMI75M1A2tKUQC';
  const track = ShareTarget(kind: ShareKind.track, id: id, title: 'Song');

  test('web url and uri follow Spotify formats', () {
    expect(track.webUrl, 'https://open.spotify.com/track/$id');
    expect(track.uri, 'spotify:track:$id');
    const artist = ShareTarget(kind: ShareKind.artist, id: id, title: 'A');
    expect(artist.webUrl, 'https://open.spotify.com/artist/$id');
  });

  test('embed code carries size and theme', () {
    final standard = track.embedCode();
    expect(standard, contains('src="https://open.spotify.com/embed/track/$id?utm_source=generator"'));
    expect(standard, contains('height="352"'));
    expect(standard, startsWith('<iframe'));
    expect(standard, endsWith('</iframe>'));

    final compactDark = track.embedCode(size: EmbedSize.compact, dark: true);
    expect(compactDark, contains('height="152"'));
    expect(compactDark, contains('utm_source=generator&theme=0'));
  });

  test('title is escaped inside the iframe attribute', () {
    const tricky = ShareTarget(kind: ShareKind.album, id: id, title: 'Rock & "Roll" <Live>');
    expect(tricky.embedCode(), contains('title="Spotify: Rock &amp; &quot;Roll&quot; &lt;Live&gt;"'));
  });

  test('only real Spotify ids are shareable', () {
    expect(track.isShareable, isTrue);
    for (final bad in ['local_1730000000000', 'liked', '', 'spotify:collection:tracks']) {
      expect(
        ShareTarget(kind: ShareKind.playlist, id: bad, title: 'x').isShareable,
        isFalse,
        reason: bad,
      );
    }
  });
}
