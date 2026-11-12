import 'dart:async';

import 'system_media_controls.dart';

/// 把多个系统媒体控制端合成一个：状态同时推给每一端，各端的按键事件合并成一路。
///
/// Windows 上 = SMTC 媒体卡片 + 任务栏歌词，二者共用 MediaControlsSync 的本机 / 远程切换与按键路由。
class MultiMediaControls implements SystemMediaControls {
  final List<SystemMediaControls> controls;

  final StreamController<MediaControlEvent> _events = StreamController.broadcast();
  final List<StreamSubscription<MediaControlEvent>> _subscriptions = [];

  MultiMediaControls(this.controls) {
    for (final c in controls) {
      _subscriptions.add(c.events.listen(_events.add));
    }
  }

  @override
  Stream<MediaControlEvent> get events => _events.stream;

  @override
  bool get needsPeriodicTimeline => controls.any((c) => c.needsPeriodicTimeline);

  @override
  Future<void> setTrack(MediaTrackInfo? track) => Future.wait([for (final c in controls) c.setTrack(track)]);

  @override
  Future<void> setPlayback(MediaPlaybackInfo info) => Future.wait([for (final c in controls) c.setPlayback(info)]);

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final c in controls) {
      c.dispose();
    }
    _events.close();
  }
}
