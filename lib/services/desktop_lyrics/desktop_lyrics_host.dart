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

  @override
  void Function(bool locked)? onLockChanged;

  @override
  void Function()? onClose;

  @override
  Future<void> show(Map<String, dynamic> snapshot) async {
    _visible = true;
    _latest = snapshot;
    try {
      await _ensureChannel();
      final window = await _obtainWindow();
      if (!_visible || !_childReady) return;
      await _deliver(window);
    } catch (error, stack) {
      debugPrint('[desktop-lyrics] 打开窗口失败: $error\n$stack');
    }
  }

  @override
  Future<void> hide() async {
    _visible = false;
    _shown = false;
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
    if (!_shown) {
      await window.show();
      _shown = true;
    }
    await window.invokeMethod<void>('snapshot', latest);
  }

  Future<dynamic> _onHostCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        _childReady = true;
        final window = _window;
        if (_visible && window != null) {
          try {
            await _deliver(window);
          } catch (error) {
            debugPrint('[desktop-lyrics] 同步歌词失败: $error');
          }
        }
      case 'setLocked':
        onLockChanged?.call(call.arguments == true);
      case 'close':
        onClose?.call();
    }
    return null;
  }
}
