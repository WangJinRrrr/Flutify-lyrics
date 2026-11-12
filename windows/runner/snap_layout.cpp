#include "snap_layout.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr wchar_t kInstanceProp[] = L"FlutifySnapLayout";

double GetDouble(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return 0;
  if (auto value = std::get_if<double>(&it->second)) return *value;
  if (auto value = std::get_if<int32_t>(&it->second)) return *value;
  if (auto value = std::get_if<int64_t>(&it->second)) return static_cast<double>(*value);
  return 0;
}

}  // namespace

SnapLayout::SnapLayout(HWND top_level, HWND flutter_view, flutter::BinaryMessenger* messenger)
    : top_level_(top_level), view_(flutter_view) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "flutify/window", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setMaximizeButton") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    has_button_ = args != nullptr;
    if (args) {
      left_ = GetDouble(*args, "left");
      top_ = GetDouble(*args, "top");
      width_ = GetDouble(*args, "width");
      height_ = GetDouble(*args, "height");
    } else {
      SetState(false, false);
    }
    result->Success();
  });

  // 子类化 Flutter 视图窗口：只改 WM_NCHITTEST，其余原样交回
  SetProp(view_, kInstanceProp, this);
  view_proc_ = reinterpret_cast<WNDPROC>(
      SetWindowLongPtr(view_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&SnapLayout::ViewProc)));
}

SnapLayout::~SnapLayout() {
  if (IsWindow(view_) && view_proc_) {
    SetWindowLongPtr(view_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(view_proc_));
    RemoveProp(view_, kInstanceProp);
  }
  channel_->SetMethodCallHandler(nullptr);
}

LRESULT CALLBACK SnapLayout::ViewProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = static_cast<SnapLayout*>(GetProp(hwnd, kInstanceProp));
  if (!self) return DefWindowProc(hwnd, message, wparam, lparam);
  if (message == WM_NCHITTEST) {
    POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    // 交给顶层窗口判定（同一线程的窗口才能用 HTTRANSPARENT 穿透）
    if (self->HitTest(pt)) return HTTRANSPARENT;
  }
  return CallWindowProc(self->view_proc_, hwnd, message, wparam, lparam);
}

bool SnapLayout::HitTest(POINT screen) const {
  if (!has_button_ || width_ <= 0 || height_ <= 0) return false;
  POINT pt = screen;
  if (!ScreenToClient(view_, &pt)) return false;
  const double scale = GetDpiForWindow(view_) / 96.0;
  const double x = pt.x / scale;
  const double y = pt.y / scale;
  return x >= left_ && x < left_ + width_ && y >= top_ && y < top_ + height_;
}

void SnapLayout::SetState(bool hovered, bool pressed) {
  if (hovered == hovered_ && pressed == pressed_) return;
  hovered_ = hovered;
  pressed_ = pressed;
  channel_->InvokeMethod("maximizeButtonState",
                         std::make_unique<EncodableValue>(EncodableMap{
                             {EncodableValue("hovered"), EncodableValue(hovered)},
                             {EncodableValue("pressed"), EncodableValue(pressed)},
                         }));
}

std::optional<LRESULT> SnapLayout::HandleTopLevel(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST: {
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (HitTest(pt)) return HTMAXBUTTON;
      break;
    }
    case WM_NCMOUSEMOVE:
      if (wparam == HTMAXBUTTON) {
        if (!hovered_) {
          // 离开非客户区按钮时收到 WM_NCMOUSELEAVE
          TRACKMOUSEEVENT track{sizeof(TRACKMOUSEEVENT), TME_LEAVE | TME_NONCLIENT, hwnd, 0};
          TrackMouseEvent(&track);
        }
        SetState(true, pressed_);
        return 0;
      }
      SetState(false, false);
      break;
    case WM_NCMOUSELEAVE:
      SetState(false, false);
      break;
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
      if (wparam == HTMAXBUTTON) {
        // 不交给 DefWindowProc：它会进入经典标题栏按钮的跟踪循环
        SetState(true, true);
        return 0;
      }
      break;
    case WM_NCLBUTTONUP:
      if (wparam == HTMAXBUTTON) {
        const bool click = pressed_;
        SetState(true, false);
        if (click) channel_->InvokeMethod("maximizeButtonClick", nullptr);
        return 0;
      }
      break;
  }
  return std::nullopt;
}
