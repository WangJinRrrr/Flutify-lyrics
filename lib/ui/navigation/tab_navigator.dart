import 'package:flutter/material.dart';

/// 每个底部 Tab 独立的嵌套 Navigator。
///
/// 详情页压入这里而不是根 Navigator，因此迷你播放器 / 桌面播放栏在浏览任意
/// 页面时都保持可见（Spotify 行为）；各 Tab 的浏览栈也互不干扰。
class TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  /// 仅当前 Tab 响应系统返回键。
  final bool active;

  /// 桌面端挂载 ContentHistory，用于顶栏的后退 / 前进。
  final List<NavigatorObserver> observers;

  const TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.root,
    required this.active,
    this.observers = const [],
  });

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<Object?>(
      enabled: active,
      onPopWithResult: (_) => navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: navigatorKey,
        observers: observers,
        onGenerateRoute: (settings) => MaterialPageRoute(settings: settings, builder: (_) => root),
      ),
    );
  }
}
