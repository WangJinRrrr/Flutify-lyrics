import 'package:flutter/material.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../widgets/connect/now_playing_source.dart';
import '../../../widgets/connect/remote_progress.dart';
import '../../../widgets/connect/remote_transport_controls.dart';
import '../../../widgets/liquid_glass.dart';
import '../../../widgets/playback_scrubber.dart';
import '../../../widgets/player_controls.dart';

/// 歌词界面底部的液态玻璃控制台：进度条 + 播放控件。
///
/// - 默认（手机全屏歌词）：上一首 / 播放暂停 / 下一首；
/// - [full] 为 true（桌面沉浸式、全屏播放器歌词视图）：额外带随机与循环；
/// - [bottom] 非空时放在播放控件下方、玻璃内部（桌面沉浸式的音量条，类似 Apple 锁屏）；
/// - 遥控远程设备时（[NowPlayingSource.isRemote]）进度与按钮都作用于远程设备，外观不变。
class LyricsGlassControls extends StatelessWidget {
  final bool full;
  final double maxWidth;
  final Widget? bottom;

  /// 见 [LiquidGlass.backdrop]：下方没有歌词滑过（宽屏沉浸式左栏）时传 false。
  final bool backdrop;

  const LyricsGlassControls({
    super.key,
    this.full = false,
    this.maxWidth = 520,
    this.bottom,
    this.backdrop = true,
  });

  @override
  Widget build(BuildContext context) {
    final remote = NowPlayingSource.isRemote(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LiquidGlass(
          backdrop: backdrop,
          borderRadius: context.tokens.radius(30),
          padding: EdgeInsets.fromLTRB(16, 6, 16, bottom == null ? 12 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...(remote ? _remote() : _local()),
              if (bottom != null) ...[const SizedBox(height: 4), bottom!],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _local() {
    final gap = full ? 20.0 : 28.0;
    return [
      const PlaybackScrubber(
        compact: true,
        activeColor: Colors.white,
        inactiveColor: Colors.white24,
        labelColor: Colors.white60,
      ),
      const SizedBox(height: 2),
      Row(
        mainAxisAlignment: full
            ? MainAxisAlignment.spaceEvenly
            : MainAxisAlignment.center,
        children: [
          if (full) const ShuffleButton(),
          const SkipButton(next: false, size: 32),
          SizedBox(width: full ? 0 : gap),
          const PlayPauseButton(size: 56, iconSize: 32),
          SizedBox(width: full ? 0 : gap),
          const SkipButton(next: true, size: 32),
          if (full) const RepeatButton(),
        ],
      ),
    ];
  }

  List<Widget> _remote() => [
    const RemoteScrubber(
      activeColor: Colors.white,
      inactiveColor: Colors.white24,
      labelColor: Colors.white60,
    ),
    const SizedBox(height: 2),
    RemoteTransportControls(
      showModes: full,
      style: full ? RemoteControlsStyle.glassFull : RemoteControlsStyle.glass,
    ),
  ];
}
