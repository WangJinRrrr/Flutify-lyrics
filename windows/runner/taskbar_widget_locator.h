#ifndef RUNNER_TASKBAR_WIDGET_LOCATOR_H_
#define RUNNER_TASKBAR_WIDGET_LOCATOR_H_

#include <windows.h>

#include <atomic>
#include <mutex>
#include <thread>

// 在后台 MTA 线程读取任务栏实际按钮边界，避免跨进程 UIA 阻塞绘制。
// Win11 的 ReBarWindow32 并不包含所有应用图标，不能用于判断空白区域。
// 每秒以一次缓存请求读取新快照，应用打开/关闭后会重新测量；不依赖本地化名称。
class TaskbarWidgetLocator {
 public:
  // 不可用（UIA 失败 / 尚未测到）
  static constexpr int kUnknown = -1;
  // 确认没有小组件
  static constexpr int kNone = 0;

  TaskbarWidgetLocator() = default;
  ~TaskbarWidgetLocator();

  TaskbarWidgetLocator(const TaskbarWidgetLocator&) = delete;
  TaskbarWidgetLocator& operator=(const TaskbarWidgetLocator&) = delete;

  void Start();
  void Stop();

  struct Bounds {
    HWND taskbar = nullptr;
    int width = 0;
    int height = 0;
    // 物理像素，相对任务栏左缘。
    int widget_left = kUnknown;
    int widget_right = kUnknown;
    int icons_left = kUnknown;
    int icons_right = kUnknown;
    int tray_left = kUnknown;
  };
  Bounds bounds() const;

 private:
  void Run();

  std::thread thread_;
  std::atomic<bool> running_{false};
  mutable std::mutex mutex_;
  Bounds bounds_;
};

#endif  // RUNNER_TASKBAR_WIDGET_LOCATOR_H_
