# Android 系统媒体控制排查

反馈：vivo 手机使用 v0.03-beta，有播放通知，但上一首、下一首、暂停按钮和进度条缺失。具体手机型号和系统版本尚未提供，未在反馈设备复现。

## 已确认的问题及修复

- 从 GitHub 下载已发布的 `Flutify-v0.03-beta-android-arm64-v8a.apk`，检查 `resources.arsc`：`audio_service_play_arrow`、`audio_service_pause`、`audio_service_skip_previous`、`audio_service_skip_next`、`audio_service_stop` 名称均不存在。audio_service 0.18.19 在原生代码中使用 `getIdentifier` 按名称加载这些图标。新增 `res/raw/keep.xml` 保留资源，并使用独立的单色通知图标。
- `MediaControlsSync` 原来仅按曲目 ID 更新元数据。若初始时长为 0，解码器后来得到实际时长，系统仍收到 0，无法形成有效时间线。现在同时比较时长、标题、专辑和封面，并使用播放器更新后的时长。
- 为暂停和缓冲上报速度 0，正常播放上报 1；进度变化检测也在缓冲时停止外推。
- 显式声明 MediaSession 的播放、暂停、切换、跳转和可用的上一首／下一首操作，保留旧版通知的紧凑按钮。插件本身已把通知关联到 MediaSession，且会将通知按钮合入原生 actions；显式声明便于验证两种展示路径，并非单独证明 vivo 根因。
- 修复 Connect 队列扩展与完整歌单分页，使“下一首”的可用性反映实际队列。

## 验证

自动测试覆盖 AudioHandler → MediaControlsSync → PlaybackProvider 的播放、暂停、上一首、下一首和 seek；包括未知时长补全、越界 seek、列表末尾禁用下一首、缓冲恢复。GitHub 构建对四个 Release APK 检查媒体图标、固定签名和 versionCode。

收到新版后，在反馈 vivo 设备上验证：播放有后续曲目的歌单，展开通知并查看锁屏控制；暂停／恢复，切换前后曲目，拖动进度；熄屏后重复操作。若仍缺失，用 `adb shell dumpsys media_session` 检查 Flutify 会话的 active、actions、state、position、speed 与 metadata duration。回传前去掉其他应用会话和个人曲目信息。

按钮缺失与发布资源裁剪吻合；仍需实机确认是否还有 OEM 展示策略差异。

## 小米澎湃 OS：系统媒体卡片不显示封面

反馈：澎湃 OS 下通知栏与控制中心的媒体通知都不显示封面（文字、按钮、进度正常）。

根因：`AudioServiceMediaControls.setTrack` 把 Spotify 的远程封面 URL（`https://i.scdn.co/...`）直接作为 `MediaItem.artUri`。audio_service 对非 `file://` 的封面是两段式下发——先发一次不带封面的 metadata，下载完成后再发第二次补上封面。MIUI / 澎湃 的系统媒体框架只渲染首次 metadata，不再为后续补发的 bitmap 重绘封面，于是封面一直为空。此外 audio_service 下载封面用的是 flutter_cache_manager 的全局 `DefaultCacheManager`，与 App 自己的 `ArtworkCache`（`CachedNetworkImageProvider.defaultCacheManager`）是两套缓存，已缓存的封面无法复用。

修复：

- 系统媒体控制创建时注入封面本地化解析器（`main.dart` 用 `ArtworkCache.getSingleFile`），`setTrack` 先把封面落到本地文件，再以 `file://` 单次下发；audio_service 对 `file://` 不走两段式。解析失败或超时（5 秒）时回退远程 URL。
- `AudioService.init` 补 `androidArtDownscaleSize`（512×512），限制 metadata 内联 bitmap 尺寸。
- 封面解析是异步的，用下发序号丢弃换曲期间完成的过期结果，避免旧封面盖住新曲目。

验证：`test/audio_service_media_controls_test.dart` 覆盖本地化下发、失败回退、无封面、换曲乱序四种路径；沿用 remote 的旧测试保持通过。真机确认仍需在澎湃设备上播放并查看通知栏 / 控制中心封面。
