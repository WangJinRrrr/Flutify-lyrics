import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_lyrics_protocol.dart';

/// 桌面歌词窗口的宿主。Android 和 Web 不创建。
abstract class DesktopLyricsController {
  Future<void> show(Map<String, dynamic> snapshot);
  Future<void> hide();
  set onLockChanged(void Function(bool locked)? value);
  set onClose(void Function()? value);
  set onOpenFailed(void Function(Object error)? value);
}

bool get desktopLyricsSupported {
  if (kIsWeb) return false;
  return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
}

DesktopLyricsController? createDesktopLyricsController() {
  if (!desktopLyricsSupported) return null;
  return DesktopLyricsWindowHost();
}

class DesktopLyricsWindowHost implements DesktopLyricsController {
  DesktopLyricsWindowHost();

  final WindowMethodChannel _host = const WindowMethodChannel(
    desktopLyricsHostChannel,
    mode: ChannelMode.unidirectional,
  );

  WindowController? _window;
  Future<WindowController>? _pending;
  Map<String, dynamic>? _latest;
  bool _channelReady = false;
  bool _childReady = false;
  bool _visible = false;
  bool _shown = false;
  Timer? _readyTimer;

  @override
  void Function(bool locked)? onLockChanged;

  @override
  void Function()? onClose;

  @override
  void Function(Object error)? onOpenFailed;

  @override
  Future<void> show(Map<String, dynamic> snapshot) async {
    _visible = true;
    _latest = snapshot;
    try {
      await _ensureChannel();
      final window = await _obtainWindow();
      // 子窗口先保持隐藏：等它把第一份快照收好再显示，避免出现空白的
      // 置顶窗口。_deliver 里会先发快照再 show。
      _armReadyTimer();
      if (!_visible || !_childReady) return;
      await _deliver(window);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  @override
  Future<void> hide() async {
    _visible = false;
    _shown = false;
    _readyTimer?.cancel();
    final window = _window;
    if (window == null) return;
    try {
      await window.hide();
    } catch (error) {
      debugPrint('[desktop-lyrics] 隐藏窗口失败: $error');
    }
  }

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    await _host.setMethodCallHandler(_onHostCall);
    _channelReady = true;
  }

  Future<WindowController> _obtainWindow() {
    final existing = _window;
    if (existing != null) return Future.value(existing);
    final pending = _pending ??= _createWindow();
    return pending.catchError((Object error) {
      if (identical(_pending, pending)) _pending = null;
      throw error;
    });
  }

  void _armReadyTimer() {
    // 播放中每秒都会调用 show()，计时器只从创建窗口时算起，不能被续命。
    if (_childReady || (_readyTimer?.isActive ?? false)) return;
    // 子窗口自己最多重试 10 秒等插件注册，主窗口多留一点余量。
    _readyTimer = Timer(const Duration(seconds: 12), () {
      _readyTimer = null;
      if (!_childReady && _visible) {
        _fail('桌面歌词窗口没有在 12 秒内就绪', StackTrace.current);
      }
    });
  }

  void _fail(Object error, StackTrace stack) {
    _readyTimer?.cancel();
    final window = _window;
    _visible = false;
    _shown = false;
    _childReady = false;
    _window = null;
    _pending = null;
    if (window != null) {
      unawaited(window.hide().catchError((Object _) {}));
    }
    debugPrint('[desktop-lyrics] 打开窗口失败，关闭开关: $error\n$stack');
    final report = onOpenFailed;
    if (report != null) report(error);
  }

  Future<WindowController> _createWindow() async {
    final created = await WindowController.create(
      const WindowConfiguration(
        arguments: desktopLyricsArgument,
        hiddenAtLaunch: true,
      ),
    );
    _window = created;
    return created;
  }

  Future<void> _deliver(WindowController window) async {
    final latest = _latest;
    if (latest == null || !_visible) return;
    // 先送第一份快照再显示，避免出现一帧空白 / 纯色的置顶窗口。
    await window.invokeMethod<void>('snapshot', latest);
    if (!_shown) {
      await window.show();
      _shown = true;
    }
  }

  /// 旧引擎在窗口重建后仍可能发来 ready / failed，只认当前窗口的消息。
  bool _fromCurrentWindow(Object? arguments) {
    final window = _window;
    if (window == null) return false;
    final id = arguments is Map ? arguments['windowId'] : arguments;
    return id is! String || id.isEmpty || id == window.windowId;
  }

  Future<dynamic> _onHostCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        if (!_fromCurrentWindow(call.arguments)) return null;
        _childReady = true;
        _readyTimer?.cancel();
        final window = _window;
        if (_visible && window != null) {
          try {
            await _deliver(window);
          } catch (error, stack) {
            _fail(error, stack);
          }
        }
      case 'failed':
        if (!_fromCurrentWindow(call.arguments)) return null;
        final arguments = call.arguments;
        final error = arguments is Map ? arguments['error'] : arguments;
        _fail(error ?? '子窗口报告失败', StackTrace.current);
      case 'setLocked':
        onLockChanged?.call(call.arguments == true);
      case 'close':
        onClose?.call();
    }
    return null;
  }
}
