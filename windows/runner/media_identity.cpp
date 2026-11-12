#include "media_identity.h"

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

namespace media_identity {
namespace {
using Microsoft::WRL::ComPtr;

std::wstring ExecutablePath() {
  wchar_t path[32768]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  return length > 0 && length < ARRAYSIZE(path)
             ? std::wstring(path, length)
             : std::wstring();
}

HRESULT SetString(IPropertyStore* store, REFPROPERTYKEY key,
                  const std::wstring& text) {
  PROPVARIANT value{};
  HRESULT result = InitPropVariantFromString(text.c_str(), &value);
  if (SUCCEEDED(result)) result = store->SetValue(key, value);
  PropVariantClear(&value);
  return result;
}
}  // namespace

HRESULT WriteShortcut(const std::wstring& path,
                      const std::wstring& executable) {
  ComPtr<IShellLinkW> link;
  HRESULT result = CoCreateInstance(CLSID_ShellLink, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
  if (FAILED(result)) return result;
  if (FAILED(result = link->SetPath(executable.c_str()))) return result;
  const auto directory = executable.substr(0, executable.find_last_of(L"\\/"));
  if (FAILED(result = link->SetWorkingDirectory(directory.c_str()))) return result;
  if (FAILED(result = link->SetDescription(L"Flutify"))) return result;
  if (FAILED(result = link->SetIconLocation(executable.c_str(), 0))) return result;
  ComPtr<IPropertyStore> properties;
  if (FAILED(result = link.As(&properties))) return result;
  if (FAILED(result = SetString(properties.Get(), PKEY_AppUserModel_ID, kAppId))) return result;
  if (FAILED(result = properties->Commit())) return result;
  ComPtr<IPersistFile> file;
  if (FAILED(result = link.As(&file))) return result;
  return file->Save(path.c_str(), TRUE);
}

void RegisterProcess() {
  SetCurrentProcessExplicitAppUserModelID(kAppId);
  const auto executable = ExecutablePath();
  if (executable.empty()) return;

  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER,
          L"Software\\Classes\\AppUserModelId\\Flutify", 0, nullptr, 0,
          KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    RegSetValueExW(key, L"DisplayName", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(kAppId), sizeof(kAppId));
    RegSetValueExW(key, L"IconUri", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(executable.c_str()),
        static_cast<DWORD>((executable.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
  }

  // Windows resolves unpackaged media-session names through its app resolver.
  // Register a per-user Start menu link, with the SAME identity as the HWND.
  // Refresh its target on launch so moving a portable build does not leave a
  // shortcut pointing to the old executable. No administrator rights needed.
  PWSTR programs = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE,
                                    nullptr, &programs))) {
    const std::wstring shortcut = std::wstring(programs) + L"\\Flutify.lnk";
    if (SUCCEEDED(WriteShortcut(shortcut, executable))) {
      SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, shortcut.c_str(), nullptr);
    }
    CoTaskMemFree(programs);
  }
}

void RegisterWindow(HWND window) {
  ComPtr<IPropertyStore> properties;
  if (FAILED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&properties)))) return;
  const auto executable = ExecutablePath();
  if (!executable.empty()) {
    SetString(properties.Get(), PKEY_AppUserModel_RelaunchCommand,
              L"\"" + executable + L"\"");
    SetString(properties.Get(), PKEY_AppUserModel_RelaunchDisplayNameResource,
              L"@" + executable + L",-101");
    SetString(properties.Get(), PKEY_AppUserModel_RelaunchIconResource,
              executable + L",0");
  }
  SetString(properties.Get(), PKEY_AppUserModel_ID, kAppId);
  properties->Commit();
}
}  // namespace media_identity
