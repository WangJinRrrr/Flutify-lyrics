import 'package:flutify_app/ui/shell/shell_layout_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 右栏两个面板：「正在播放」由播放状态键开关，「播放队列」由队列键开关，互不干扰。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playback status key toggles the now-playing panel', () {
    final layout = ShellLayoutController();
    expect(layout.playbackStatusVisible, isTrue); // 停靠右栏默认打开在「正在播放」

    layout.togglePlaybackStatus();
    expect(layout.rightPanelVisible, isFalse);

    layout.togglePlaybackStatus();
    expect(layout.panel, RightPanel.nowPlaying);
    expect(layout.playbackStatusVisible, isTrue);
  });

  test('queue key switches panels instead of closing, and closes its own panel', () {
    final layout = ShellLayoutController();
    layout.togglePanel(RightPanel.queue);
    expect(layout.isShowing(RightPanel.queue), isTrue);
    expect(layout.playbackStatusVisible, isFalse);

    // 队列显示中按播放状态键：切到「正在播放」而不是关闭
    layout.togglePlaybackStatus();
    expect(layout.rightPanelVisible, isTrue);
    expect(layout.panel, RightPanel.nowPlaying);

    layout.togglePanel(RightPanel.queue);
    layout.togglePanel(RightPanel.queue);
    expect(layout.rightPanelVisible, isFalse);

    // 面板内的「播放队列」入口：总是打开，不会误关
    layout.switchPanel(RightPanel.queue);
    expect(layout.isShowing(RightPanel.queue), isTrue);
    layout.switchPanel(RightPanel.queue);
    expect(layout.isShowing(RightPanel.queue), isTrue);
  });

  test('lyrics expansion is remembered across launches', () async {
    final layout = ShellLayoutController();
    await Future<void>.delayed(Duration.zero);
    expect(layout.lyricsExpanded, isFalse);
    layout.toggleLyricsExpanded();
    expect(layout.lyricsExpanded, isTrue);

    final restored = ShellLayoutController();
    await Future<void>.delayed(Duration.zero);
    expect(restored.lyricsExpanded, isTrue);
  });
}
