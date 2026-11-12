/// 由 `main` 在看到 `--desktop-lyrics-smoke` 时置位。
///
/// 冒烟测试用它打开一条示例歌词，不登录 Spotify。子窗口进程不会读到这个标志。
bool desktopLyricsSmokeRequested = false;
