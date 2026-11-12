#ifndef RUNNER_GDIPLUS_INCLUDE_H_
#define RUNNER_GDIPLUS_INCLUDE_H_

// GDI+ 头文件依赖 min / max 宏，而本工程定义了 NOMINMAX：先把 std 版本引入 Gdiplus 命名空间。
// 头文件本身在 /W4 /WX 下有告警，单独降级。
#include <windows.h>
#include <objidl.h>

#include <algorithm>

namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus

#pragma warning(push, 0)
#include <gdiplus.h>
#pragma warning(pop)

#endif  // RUNNER_GDIPLUS_INCLUDE_H_
