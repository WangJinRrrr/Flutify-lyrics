#include "media_controls.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// C++/WinRT 头文件在 /W4 /WX 下会产生与本项目无关的告警，单独降级
#pragma warning(push, 0)
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#pragma warning(pop)

#include <algorithm>
#include <chrono>
#include <optional>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;

// 本类投递给窗口的私有消息（WM_APP 段，避开 Flutter / 插件常用的值）。
constexpr UINT kButtonMessage = WM_APP + 0x51;
constexpr UINT kSeekMessage = WM_APP + 0x52;

std::string GetString(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return {};
  if (auto value = std::get_if<std::string>(&it->second)) return *value;
  return {};
}

bool GetBool(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return false;
  if (auto value = std::get_if<bool>(&it->second)) return *value;
  return false;
}

int64_t GetInt(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return 0;
  if (auto value = std::get_if<int32_t>(&it->second)) return *value;
  if (auto value = std::get_if<int64_t>(&it->second)) return *value;
  return 0;
}

winrt::Windows::Foundation::TimeSpan Millis(int64_t ms) {
  return std::chrono::duration_cast<winrt::Windows::Foundation::TimeSpan>(std::chrono::milliseconds(ms));
}

const char* ButtonName(SystemMediaTransportControlsButton button) {
  switch (button) {
    case SystemMediaTransportControlsButton::Play:
      return "play";
    case SystemMediaTransportControlsButton::Pause:
      return "pause";
    case SystemMediaTransportControlsButton::Stop:
      return "stop";
    case SystemMediaTransportControlsButton::Next:
      return "next";
    case SystemMediaTransportControlsButton::Previous:
      return "previous";
    default:
      return nullptr;
  }
}

}  // namespace

struct MediaControls::Impl {
  HWND window;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  SystemMediaTransportControls smtc{nullptr};
  winrt::event_token button_token{};
  winrt::event_token seek_token{};
  int64_t duration_ms = 0;

  Impl(HWND hwnd, flutter::BinaryMessenger* messenger) : window(hwnd) {
    channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        messenger, "flutify/media_controls", &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto& call, auto result) { OnMethodCall(call, std::move(result)); });

    try {
      // 桌面（Win32）程序须通过 Interop 按窗口取得 SMTC
      auto interop = winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
      winrt::check_hresult(interop->GetForWindow(window, winrt::guid_of<SystemMediaTransportControls>(),
                                                 winrt::put_abi(smtc)));
      smtc.IsPlayEnabled(true);
      smtc.IsPauseEnabled(true);
      smtc.IsStopEnabled(true);
      smtc.IsNextEnabled(true);
      smtc.IsPreviousEnabled(true);
      smtc.IsEnabled(false);  // 有曲目后才显示媒体卡片
      smtc.DisplayUpdater().Type(MediaPlaybackType::Music);

      HWND target = window;
      button_token = smtc.ButtonPressed(
          [target](const SystemMediaTransportControls&, const SystemMediaTransportControlsButtonPressedEventArgs& args) {
            PostMessage(target, kButtonMessage, static_cast<WPARAM>(args.Button()), 0);
          });
      seek_token = smtc.PlaybackPositionChangeRequested(
          [target](const SystemMediaTransportControls&, const PlaybackPositionChangeRequestedEventArgs& args) {
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(args.RequestedPlaybackPosition()).count();
            PostMessage(target, kSeekMessage, 0, static_cast<LPARAM>(ms));
          });
    } catch (...) {
      smtc = nullptr;  // 系统不支持（如精简版 Windows）：Dart 端调用照常返回，只是没有效果
    }
  }

  ~Impl() {
    if (smtc) {
      try {
        smtc.ButtonPressed(button_token);
        smtc.PlaybackPositionChangeRequested(seek_token);
        smtc.IsEnabled(false);
      } catch (...) {
      }
    }
    channel->SetMethodCallHandler(nullptr);
  }

  void OnMethodCall(const flutter::MethodCall<EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!smtc) {
      result->Success();
      return;
    }
    try {
      const auto* args = std::get_if<EncodableMap>(call.arguments());
      if (call.method_name() == "setTrack") {
        SetTrack(args);
      } else if (call.method_name() == "setPlayback") {
        if (args) SetPlayback(*args);
      } else {
        result->NotImplemented();
        return;
      }
      result->Success();
    } catch (const winrt::hresult_error& e) {
      result->Error("smtc", winrt::to_string(e.message()));
    } catch (...) {
      result->Error("smtc", "unknown error");
    }
  }

  void SetTrack(const EncodableMap* args) {
    auto updater = smtc.DisplayUpdater();
    if (!args) {
      updater.ClearAll();
      updater.Update();
      smtc.PlaybackStatus(MediaPlaybackStatus::Closed);
      smtc.IsEnabled(false);
      duration_ms = 0;
      return;
    }
    updater.Type(MediaPlaybackType::Music);
    auto music = updater.MusicProperties();
    music.Title(winrt::to_hstring(GetString(*args, "title")));
    music.Artist(winrt::to_hstring(GetString(*args, "artist")));
    music.AlbumTitle(winrt::to_hstring(GetString(*args, "album")));
    const auto art = GetString(*args, "artUrl");
    if (art.empty()) {
      updater.Thumbnail(nullptr);
    } else {
      updater.Thumbnail(winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(
          winrt::Windows::Foundation::Uri(winrt::to_hstring(art))));
    }
    updater.Update();
    duration_ms = GetInt(*args, "durationMs");
    smtc.IsEnabled(true);
  }

  void SetPlayback(const EncodableMap& args) {
    const bool playing = GetBool(args, "playing");
    smtc.PlaybackStatus(playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
    smtc.IsNextEnabled(GetBool(args, "canNext"));
    smtc.IsPreviousEnabled(GetBool(args, "canPrevious"));
    if (duration_ms > 0) {
      SystemMediaTransportControlsTimelineProperties timeline;
      timeline.StartTime(Millis(0));
      timeline.MinSeekTime(Millis(0));
      timeline.EndTime(Millis(duration_ms));
      timeline.MaxSeekTime(Millis(duration_ms));
      timeline.Position(Millis(std::min(GetInt(args, "positionMs"), duration_ms)));
      smtc.UpdateTimelineProperties(timeline);
    }
  }
};

MediaControls::MediaControls(HWND window, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(window, messenger)) {}

MediaControls::~MediaControls() = default;

bool MediaControls::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kButtonMessage) {
    const char* name = ButtonName(static_cast<SystemMediaTransportControlsButton>(wparam));
    if (name) impl_->channel->InvokeMethod("button", std::make_unique<EncodableValue>(std::string(name)));
    return true;
  }
  if (message == kSeekMessage) {
    impl_->channel->InvokeMethod("seek", std::make_unique<EncodableValue>(static_cast<int64_t>(lparam)));
    return true;
  }
  return false;
}
