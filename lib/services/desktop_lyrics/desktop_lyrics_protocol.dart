/// 子窗口启动参数。desktop_multi_window 把它放进引擎参数的第三项。
const String desktopLyricsArgument = 'desktop_lyrics';

/// 子窗口回调主窗口用的单向通道：就绪、锁定、关闭。
const String desktopLyricsHostChannel = 'flutify/desktop_lyrics_host';

bool isDesktopLyricsEntrypoint(List<String> args) {
  return args.length >= 3 &&
      args.first == 'multi_window' &&
      args[2] == desktopLyricsArgument;
}
