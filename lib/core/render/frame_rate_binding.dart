import 'dart:async';

import 'package:flutter/widgets.dart';

/// 带整窗帧率上限的 binding（设置页「帧率上限」）。
///
/// 所有重绘最终都经 [scheduleFrame] 向引擎申请 vsync；这里在申请前按上限推迟：
/// 距上一帧不足一个间隔时，用定时器等到「间隔 - 半个屏幕帧」再申请，
/// 让随后到来的 vsync 平均落在间隔附近。动画、滚动都按帧时间戳推进，
/// 所以速度不变、只是出帧更少；上限不低于屏幕刷新率时完全不介入。
class FrameRateBinding extends WidgetsFlutterBinding {
  static FrameRateBinding ensureInitialized() {
    if (_instance == null) FrameRateBinding();
    return _instance!;
  }

  static FrameRateBinding? _instance;

  /// 测试等环境下 binding 不是本类时返回 null。
  static FrameRateBinding? get maybeInstance => _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastFrameAt = Duration.zero;
  Timer? _deferred;
  int _limit = 0;

  /// 帧率上限（fps）；0 = 跟随屏幕。
  int get frameRateLimit => _limit;
  set frameRateLimit(int value) {
    if (value == _limit) return;
    _limit = value;
    // 改档时立即放行积压的申请，新间隔从下一帧起生效
    if (_deferred != null) {
      _deferred!.cancel();
      _deferred = null;
      super.scheduleFrame();
    }
  }

  /// 屏幕刷新率；部分平台报 0 时按 60 处理。
  double get _displayHz {
    final displays = platformDispatcher.displays;
    final hz = displays.isEmpty ? 0.0 : displays.first.refreshRate;
    return hz > 1 ? hz : 60;
  }

  /// 生效的最小帧间隔；不限或上限不低于屏幕刷新率时为 null。
  Duration? get _interval {
    if (_limit <= 0 || _limit >= _displayHz - 0.5) return null;
    return Duration(microseconds: 1000000 ~/ _limit);
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _lastFrameAt = _clock.elapsed;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void scheduleFrame() {
    final interval = _interval;
    if (interval == null || hasScheduledFrame || !framesEnabled) {
      super.scheduleFrame();
      return;
    }
    if (_deferred != null) return;
    final vsyncLead = Duration(microseconds: 500000 ~/ _displayHz);
    final wait = interval - (_clock.elapsed - _lastFrameAt) - vsyncLead;
    if (wait <= Duration.zero) {
      super.scheduleFrame();
      return;
    }
    _deferred = Timer(wait, () {
      _deferred = null;
      super.scheduleFrame();
    });
  }
}
