#ifndef RUNNER_MEDIA_IDENTITY_H_
#define RUNNER_MEDIA_IDENTITY_H_

#include <windows.h>
#include <string>

// A portable Win32 app needs a shell shortcut as well as a process AUMID.
namespace media_identity {
inline constexpr wchar_t kAppId[] = L"Flutify";
void RegisterProcess();
void RegisterWindow(HWND window);
// Explicit path also allows verification without modifying the Start menu.
HRESULT WriteShortcut(const std::wstring& path, const std::wstring& executable);
}  // namespace media_identity

#endif  // RUNNER_MEDIA_IDENTITY_H_
