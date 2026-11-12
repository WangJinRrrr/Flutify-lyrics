import CFNetwork
import Cocoa
import FlutterMacOS

/// MethodChannel `flutify/system_proxy`（Dart 端见 lib/services/network/system_proxy_channel.dart）。
///
/// GUI 应用不继承 shell 的 http_proxy 环境变量，Dart 端通过本通道读取
/// 「系统设置 → 网络 → 代理」。只返回简单类型（Bool / Int / String / String 数组）：
///
///   getSystemProxySettings → {
///     httpEnabled: Bool, httpHost: String, httpPort: Int,
///     httpsEnabled: Bool, httpsHost: String, httpsPort: Int,
///     socksEnabled: Bool, socksHost: String, socksPort: Int,
///     pacEnabled: Bool, pacUrl: String,
///     exceptions: [String],
///     excludeSimpleHostnames: Bool,
///     ftpPassive: Bool,
///   }
final class SystemProxyChannel {
  static let channelName = "flutify/system_proxy"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getSystemProxySettings":
        result(systemProxySettings())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// CFNetworkCopySystemProxySettings 的字典里混有 CFNumber / CFString / CFArray，
  /// 桥接成 [String: Any] 后逐个按键收敛成简单类型，避免把 CF 类型直接塞进 codec。
  /// 读取失败返回 nil：Dart 侧据此回退环境变量（空字典会被当成「没有代理」而直连）。
  private static func systemProxySettings() -> [String: Any]? {
    guard let proxies = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
      as? [String: Any]
    else {
      return nil
    }

    func flag(_ key: String) -> Bool {
      (proxies[key] as? NSNumber)?.boolValue ?? false
    }
    func host(_ key: String) -> String {
      (proxies[key] as? String) ?? ""
    }
    func port(_ key: String) -> Int {
      (proxies[key] as? NSNumber)?.intValue ?? 0
    }

    return [
      "httpEnabled": flag(kCFNetworkProxiesHTTPEnable as String),
      "httpHost": host(kCFNetworkProxiesHTTPProxy as String),
      "httpPort": port(kCFNetworkProxiesHTTPPort as String),
      "httpsEnabled": flag(kCFNetworkProxiesHTTPSEnable as String),
      "httpsHost": host(kCFNetworkProxiesHTTPSProxy as String),
      "httpsPort": port(kCFNetworkProxiesHTTPSPort as String),
      "socksEnabled": flag(kCFNetworkProxiesSOCKSEnable as String),
      "socksHost": host(kCFNetworkProxiesSOCKSProxy as String),
      "socksPort": port(kCFNetworkProxiesSOCKSPort as String),
      "pacEnabled": flag(kCFNetworkProxiesProxyAutoConfigEnable as String),
      "pacUrl": host(kCFNetworkProxiesProxyAutoConfigURLString as String),
      "exceptions": proxies[kCFNetworkProxiesExceptionsList as String] as? [String] ?? [],
      // macOS 无 <local> 规则，等价键单独给出（macOS 10.16+ 的「忽略这些主机与域的简单主机名」）
      "excludeSimpleHostnames": flag("ExcludeSimpleHostnames"),
      "ftpPassive": flag(kCFNetworkProxiesFTPPassive as String),
    ]
  }
}
