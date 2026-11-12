#ifndef RUNNER_SNAP_LAYOUT_H_
#define RUNNER_SNAP_LAYOUT_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>

// Windows 11 分屏布局（Snap Layouts）：鼠标停在最大化按钮上时弹出的分屏选择器。
//
// 系统只在顶层窗口对 WM_NCHITTEST 返回 HTMAXBUTTON 时才弹出它，而本 App 的最大化按钮是 Flutter 自绘的：
// 1. Dart 把自绘最大化按钮的位置（逻辑像素，相对 Flutter 视图）通过 `flutify/window` 的
//    setMaximizeButton 发过来（按钮不显示时为 null）；
// 2. Flutter 子窗口在这块区域对 WM_NCHITTEST 返回 HTTRANSPARENT，命中测试落到顶层窗口，
//    顶层窗口返回 HTMAXBUTTON → 系统弹出分屏选择器；
// 3. 这块区域的鼠标消息变成非客户区消息，Flutter 收不到，于是由这里把悬停 / 按下状态
//    （maximizeButtonState）与点击（maximizeButtonClick）回传给 Dart 绘制与执行。
class SnapLayout {
 public:
  SnapLayout(HWND top_level, HWND flutter_view, flutter::BinaryMessenger* messenger);
  ~SnapLayout();

  SnapLayout(const SnapLayout&) = delete;
  SnapLayout& operator=(const SnapLayout&) = delete;

  // 顶层窗口消息；需要拦截时返回结果。
  std::optional<LRESULT> HandleTopLevel(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  static LRESULT CALLBACK ViewProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  // 屏幕坐标是否落在最大化按钮上。
  bool HitTest(POINT screen) const;
  void SetState(bool hovered, bool pressed);

  HWND top_level_;
  HWND view_;
  WNDPROC view_proc_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // 最大化按钮在 Flutter 视图中的位置（逻辑像素）。
  bool has_button_ = false;
  double left_ = 0, top_ = 0, width_ = 0, height_ = 0;

  bool hovered_ = false;
  bool pressed_ = false;
};

#endif  // RUNNER_SNAP_LAYOUT_H_
