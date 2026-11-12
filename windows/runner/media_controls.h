#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Windows 系统媒体控制（SMTC）：任务栏 / 锁屏 / 快速设置里的媒体卡片与键盘媒体键。
//
// MethodChannel `flutify/media_controls`（Dart 端见 lib/services/media_controls/windows_media_controls.dart）：
//   Dart → 原生：setTrack({title, artist, album, artUrl, durationMs} | null)、
//               setPlayback({playing, buffering, positionMs, canNext, canPrevious})
//   原生 → Dart：button("play" | "pause" | "stop" | "next" | "previous")、seek(毫秒)
//
// SMTC 的事件在后台线程触发，先 PostMessage 回窗口线程，再由 HandleMessage 转给 Dart。
class MediaControls {
 public:
  MediaControls(HWND window, flutter::BinaryMessenger* messenger);
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // 顶层窗口消息；处理了本类投递的消息时返回 true。
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
