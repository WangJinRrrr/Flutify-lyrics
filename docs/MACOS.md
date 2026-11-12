# macOS 开发与自测

macOS 测试版随 GitHub Releases 提供 `Flutify-<版本>-macos.zip`，解压后将 `Flutify.app` 放入应用程序目录。包内 `.app` 未做 Developer ID 签名或 Apple 公证，首次打开可能需要在系统设置的“隐私与安全性”中允许打开。

## 构建

需要 Xcode（含命令行工具）、CocoaPods 与 Flutter 3.44.9 及以上（CI 的 macOS 任务固定 3.44.9；其他平台仍为 3.44.0）。Xcode 工程与 Podfile 的最低系统版本为 macOS 12.0（较新的 Xcode 不再支持更低的部署目标）；这不是所有系统版本均完成实机验证的声明。

在仓库根目录运行：

```sh
flutter pub get
flutter test
flutter build macos --release
open build/macos/Build/Products/Release/Flutify.app
```

Podfile 与 `Podfile.lock` 纳入版本控制；Pods 和 Flutter ephemeral 目录不提交。首次构建会由 Flutter 调用 `pod install`。若缓存不一致，可执行 `flutter clean` 后重跑上述命令。

开发版可用 `flutter run -d macos`。自测 Release 时请通过 `open` 启动 `.app`，不要在终端后台直接执行二进制：macOS 无头 WKWebView 的创建依赖已显示、聚焦的主窗口。

Xcode 27 的 `lipo` 一次只接受一个 `-verify_arch` 参数，Flutter 3.44.0–3.44.8 的 `flutter_tools` 仍按旧行为一次校验多个架构，通用（x86_64 + arm64）Release 构建会在 `release_unpack_macos` 阶段报 “does not contain architectures”。该问题已在 Flutter 3.44.9 修复（[flutter/flutter#188625](https://github.com/flutter/flutter/pull/188625)），CI 的 macOS 任务固定 3.44.9；本地使用更早版本时需升级 Flutter，或按该 PR 自行打补丁。

## 适配内容

- **窗口与菜单**：使用 macOS 原生红绿灯按钮，保留顶部拖动区与安全间距；支持菜单栏、编辑菜单、Command 快捷键和原生视图响应链。
- **系统媒体控制**：通过 `flutify/media_controls` 连接 `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`，同步歌曲、封面、进度、暂停和跳转命令。
- **系统代理**：`flutify/system_proxy` 使用 CFNetwork 读取系统代理配置，Dart 端负责 HTTP / HTTPS 选路、例外列表和环境变量回退。PAC / SOCKS 不作为本次支持范围。
- **手动代理认证**：HTTP / HTTPS / AP CONNECT 支持 Basic 凭据；密码存储与偏好 JSON 分离，不进入诊断摘要，代理认证头不转发给目标服务器。
- **播放链路**：macOS 选择 CBCS 音频，通过 WebKit 原生 HLS 与 FairPlay 处理许可证；其他平台保留原有播放引擎。许可证仍由服务端决定是否授权。
- **歌词**：双语歌词保留原文、按时间轴对齐译文；双语开关控制预取，翻译按钮和自动翻译也可查找网易云已有译词。桌面沉浸式歌词支持歌词 / 队列面板切换与间奏提示。
- **现有功能兼容**：保留上游的自动反代选路、缓存目录选择与迁移、启动阶段提示和 Windows ARM64 打包；译文缓存跟随歌词缓存目录。
- **缓存路径**：只将 macOS 系统固定的 `/var`、`/tmp` 别名规范化到 `/private`，避免误拒绝缓存迁移；自定义目录和缓存子目录的符号链接仍被拒绝，目录包含关系也按规范路径检查。

## 验证

```sh
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
node --test tool/test_release_config.cjs tool/test_consent_auto_approve.cjs
python3 -m unittest discover -s tool -p test_verify_android_apks.py
flutter build macos --release
```

仓库保留部分 lint info 与工具探针 warning，上述分析命令允许这些提示，但仍对编译错误失败；这不代表零告警。与本次适配直接相关的测试涵盖 FairPlay 数据选择、本地播放服务生命周期、代理解析及认证、菜单和窗口布局、媒体快捷键、双语歌词与缓存失效。

`test/windows_trust_store_test.dart` 中依赖 Windows 信任库的 TLS 用例在 macOS 跳过；不能据此宣称 macOS 信任库也已验证。

发布前仍需手工验证：登录、连续播放及切歌、前后台恢复、菜单编辑操作、媒体键、代理网络切换、修改缓存目录、双语歌词开关及 Connect 遥控。本次自动化验证不使用或提交真实账号凭据。

## CI 与分发边界

`.github/workflows/build.yml` 新增 macOS 测试与 Release 构建任务，将 `Flutify-<构建标签>-macos.zip` 上传到本次运行的 `macos` Artifact。构建标签沿用 `prepare` 任务，支持标签和手动构建。

Release 等待 Android、Windows 和 macOS 全部构建成功后，下载三端 Artifact，并校验九个安装包齐全后生成 `SHA256SUMS.txt`。macOS ZIP 包含 `.app`，与 Windows / Android 使用同一版本标签；Developer ID 签名和 Apple 公证尚未配置。
