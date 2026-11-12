/// 子窗口启动参数。desktop_multi_window 把它放进引擎参数的第三项。
const String desktopLyricsArgument = 'desktop_lyrics';

/// 子窗口回调主窗口用的单向通道：就绪、锁定、关闭。
const String desktopLyricsHostChannel = 'flutify/desktop_lyrics_host';

bool isDesktopLyricsEntrypoint(List<String> args) {
  // 子引擎的第一个参数固定是 multi_window。只要是子引擎，就绝不能再跑主应用。
  return args.isNotEmpty && args.first == 'multi_window';
}
