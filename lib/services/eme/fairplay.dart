/// FairPlay（FPS）辅助：把 Widevine 形态的播放素材换算成 WKWebView EME 可消费的 FairPlay 形态。
///
/// 端点与协议细节对齐 Spotify Web 播放器（vendor~web-player）的 EME 客户端，
/// 并经线上接口实测校准（2026-10，见 docs/DEVELOPMENT.md「macOS 适配」）：
/// - keySystem：hls.js 1.5.x 内部映射 `com.apple.streamingkeydelivery → com.apple.fps`
///   （melody license_url 接口则以 `com.apple.fps.1_0` 识别）；
/// - 证书：GET `https://<host>/fairplay-license/v1/application-certificate`（带鉴权）；
/// - license：POST `https://<host>/fairplay-license/v1/audio/license?assetId=hex`，
///   请求体为 CDM 原样 SPC，HTTP 200 响应体即 CKC（原样喂回 session.update）；
/// - **content ID = 音频文件的 file_id（裸 40 位 hex，不带 skd:// scheme）**：
///   sneaktables `?drm=FAIRPLAY` 把 URI 吐成 `skd:///fairplay-license/v1/audio/license/<file_id>`、
///   `?drm=4` 吐 `KEYID=<file_id>`；实测只有裸 file_id 形态的 content ID 能换到 200 CKC，
///   skd:// 前缀 / KID 截断 / 其余派生 id 的 SPC 一律 500。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// hls.js 1.5.x 对 FairPlay 使用的 keySystem 字符串（不是 `com.apple.fps.1_0`）。
const String fairPlayKeySystem = 'com.apple.fps';

/// FairPlay 清单 KEY 行的 KEYFORMAT 标识。
const String fairPlayKeyFormat = 'com.apple.streamingkeydelivery';

/// FairPlay license 端点（`?assetId=hex` 是字面量：告知服务端 SPC 里的 assetId 是 hex 编码）。
Uri fairPlayLicenseUri(String host) =>
    Uri.parse('https://$host/fairplay-license/v1/audio/license?assetId=hex');

/// FairPlay application-certificate 端点（喂 setServerCertificate 的原始字节）。
Uri fairPlayCertUri(String host) =>
    Uri.parse('https://$host/fairplay-license/v1/application-certificate');

/// 从 file_id 生成 FairPlay 形态的 EXT-X-KEY 行。
///
/// 清单 URI 必须带 `skd://` scheme（hls.js 以 URI 形态存储，且 KEYFORMAT 已声明
/// streamingkeydelivery）；喂给 CDM 的 initData 由 JS 端 generateRequest 过滤器
/// 剥掉 scheme、只留 file_id 裸值（见 eme_player.dart 的 fpsDrmSystems 注释）。
String fairPlayKeyLine(String fileIdHex) =>
    '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://$fileIdHex",'
    'KEYFORMATVERSIONS="1",KEYFORMAT="$fairPlayKeyFormat"';

/// 测试注入：非 null 时覆盖平台判定（见 [useFairPlay]）。
@visibleForTesting
bool? debugUseFairPlayOverride;

/// 当前平台的 EME 是否走 FairPlay（唯一判定入口）。
///
/// macOS / iOS 都由 WKWebView 承载 EME：WebKit 只有 FairPlay、没有 Widevine；
/// Windows（WebView2）走 Widevine，Android 走原生 ExoPlayer Widevine 引擎（不经本页）。
/// 选文件（cbcs）、license 端点、页面 keySystem、错误提示文案必须用同一判定，
/// 否则端点与 CDM 错配——各处一律调用这里，不要再直接写 `Platform.isMacOS`。
bool get useFairPlay =>
    debugUseFairPlayOverride ?? (Platform.isMacOS || Platform.isIOS);
