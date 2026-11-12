#include "taskbar_widget_locator.h"

#include <UIAutomation.h>
#include <oleauto.h>

#include <algorithm>
#include <string>

namespace {

// COM 接口的最小 RAII 包装（避免为一个文件引入 WRL / ATL）。
template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ~ComPtr() { Reset(); }
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  T** Put() {
    Reset();
    return &ptr_;
  }
  T* operator->() const { return ptr_; }
  T* Get() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }
  void Reset() {
    if (ptr_) ptr_->Release();
    ptr_ = nullptr;
  }

 private:
  T* ptr_ = nullptr;
};

constexpr int kIntervalMs = 1000;

std::wstring CachedString(IUIAutomationElement* element, PROPERTYID property) {
  VARIANT value;
  VariantInit(&value);
  std::wstring result;
  if (SUCCEEDED(element->GetCachedPropertyValue(property, &value)) && value.vt == VT_BSTR && value.bstrVal) {
    result = value.bstrVal;
  }
  VariantClear(&value);
  return result;
}

}  // namespace

TaskbarWidgetLocator::~TaskbarWidgetLocator() { Stop(); }

void TaskbarWidgetLocator::Start() {
  if (running_.exchange(true)) return;
  thread_ = std::thread([this] { Run(); });
}

void TaskbarWidgetLocator::Stop() {
  running_ = false;
  if (thread_.joinable()) thread_.join();
}

TaskbarWidgetLocator::Bounds TaskbarWidgetLocator::bounds() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return bounds_;
}

void TaskbarWidgetLocator::Run() {
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return;
  {
    ComPtr<IUIAutomation> uia;
    ComPtr<IUIAutomationCondition> condition;
    ComPtr<IUIAutomationCacheRequest> cache;
    if (SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
                                   reinterpret_cast<void**>(uia.Put())))) {
      uia->CreateTrueCondition(condition.Put());
      if (SUCCEEDED(uia->CreateCacheRequest(cache.Put()))) {
        cache->AddProperty(UIA_AutomationIdPropertyId);
        cache->AddProperty(UIA_ClassNamePropertyId);
        cache->AddProperty(UIA_BoundingRectanglePropertyId);
        cache->AddProperty(UIA_IsOffscreenPropertyId);
        cache->put_AutomationElementMode(AutomationElementMode_None);
      }
    }

    int null_runs = 0;
    HWND previous_tray = nullptr;
    while (running_) {
      Bounds next;
      if (uia && condition && cache) {
        HWND tray_hwnd = FindWindowW(L"Shell_TrayWnd", nullptr);
        if (tray_hwnd != previous_tray) null_runs = 0;
        previous_tray = tray_hwnd;
        RECT tray_rect{};
        ComPtr<IUIAutomationElement> tray;
        ComPtr<IUIAutomationElementArray> elements;
        if (tray_hwnd && GetWindowRect(tray_hwnd, &tray_rect) &&
            SUCCEEDED(uia->ElementFromHandle(tray_hwnd, tray.Put())) && tray &&
            SUCCEEDED(tray->FindAllBuildCache(TreeScope_Descendants, condition.Get(), cache.Get(), elements.Put())) && elements) {
          next.taskbar = tray_hwnd;
          next.width = tray_rect.right - tray_rect.left;
          next.height = tray_rect.bottom - tray_rect.top;
          int count = 0;
          elements->get_Length(&count);
          for (int i = 0; i < count; ++i) {
            ComPtr<IUIAutomationElement> element;
            RECT box{};
            BOOL offscreen = TRUE;
            if (FAILED(elements->GetElement(i, element.Put())) || !element ||
                FAILED(element->get_CachedBoundingRectangle(&box)) ||
                FAILED(element->get_CachedIsOffscreen(&offscreen)) || offscreen ||
                box.right <= box.left || box.bottom <= box.top ||
                box.bottom <= tray_rect.top || box.top >= tray_rect.bottom) continue;
            const auto id = CachedString(element.Get(), UIA_AutomationIdPropertyId);
            const auto cls = CachedString(element.Get(), UIA_ClassNamePropertyId);
            const int left = (std::max)(0L, box.left - tray_rect.left);
            const int right = (std::min)(static_cast<LONG>(next.width), box.right - tray_rect.left);
            if (id == L"WidgetsButton") {
              next.widget_left = left;
              next.widget_right = right;
            } else if (cls == L"Taskbar.TaskListButtonAutomationPeer" || id.rfind(L"Appid:", 0) == 0 ||
                       id == L"StartButton" || id == L"SearchButton" || id == L"TaskViewButton" ||
                       id == L"CopilotButton" || id == L"ChatButton" || id == L"OverflowButton") {
              next.icons_left = next.icons_left < 0 ? left : (std::min)(next.icons_left, left);
              next.icons_right = (std::max)(next.icons_right, right);
            } else if (cls.rfind(L"SystemTray.", 0) == 0) {
              next.tray_left = next.tray_left < 0 ? left : (std::min)(next.tray_left, left);
            }
          }
          if (next.widget_right < 0) {
            if (++null_runs >= 2) next.widget_right = kNone;
          } else {
            null_runs = 0;
          }
        } else {
          null_runs = 0;
        }
      }
      {
        std::lock_guard<std::mutex> lock(mutex_);
        bounds_ = next;
      }
      for (int waited = 0; waited < kIntervalMs && running_; waited += 100) Sleep(100);
    }
  }
  CoUninitialize();
}
