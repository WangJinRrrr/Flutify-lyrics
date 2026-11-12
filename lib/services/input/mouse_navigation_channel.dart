import 'dart:io';

import 'package:flutter/services.dart';

import '../../ui/navigation/app_routes.dart';

/// macOS 鼠标侧键前进 / 后退的原生通道（MethodChannel `flutify/mouse_navigation`）。
///
/// Logi Options+ 等驱动把 MX 系列侧键作为「页面滑动」(NSEventTypeSwipe) 发送，
/// Flutter 引擎不处理 swipe 事件（原生端见 macos/Runner/MainFlutterWindow.swift 的
/// MouseNavigationChannel）；原生端监听后经本通道推送 `back` / `forward`，
/// 这里接到 [AppRoutes] 的内容历史桥，与顶栏 ‹ ›、Alt+←/→ 行为一致。
void installMacOSMouseNavigation() {
  if (!Platform.isMacOS) return;
  const channel = MethodChannel('flutify/mouse_navigation');
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'back':
        AppRoutes.navigateBack?.call();
      case 'forward':
        AppRoutes.navigateForward?.call();
    }
    return null;
  });
}
