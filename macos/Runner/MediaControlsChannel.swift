import Cocoa
import FlutterMacOS
import MediaPlayer

/// macOS 系统媒体控制（Now Playing + 键盘媒体键 / Control Center / 触控栏）。
///
/// MethodChannel `flutify/media_controls`，协议与 Windows SMTC 端一致
/// （Dart 端见 lib/services/media_controls/macos_media_controls.dart）：
///   Dart → 原生：setTrack({title, artist, album, artUrl, durationMs} | null)、
///               setPlayback({playing, buffering, positionMs, canNext, canPrevious})
///   原生 → Dart：button("play" | "pause" | "toggle" | "next" | "previous")、seek(毫秒)
///
/// 进度由系统按 rate + elapsedTime 自行推算，Dart 端无需周期性回写时间线。
final class MediaControlsChannel: NSObject {
  static let channelName = "flutify/media_controls"

  /// 持有单例：method call handler 只弱引用不到，这里强行保活。
  static var shared: MediaControlsChannel?

  private let channel: FlutterMethodChannel

  private var title = ""
  private var artist = ""
  private var album = ""
  private var artUrl = ""
  private var durationMs = 0
  private var positionMs = 0
  private var positionUpdatedAt = ProcessInfo.processInfo.systemUptime
  private var playing = false
  private var buffering = false
  private var loadedArtworkUrl = ""

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = MediaControlsChannel(channel: channel)
    handler.installRemoteCommands()
    channel.setMethodCallHandler(handler.handle)
    shared = handler
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTrack":
      setTrack(call.arguments as? [String: Any])
      result(nil)
    case "setPlayback":
      setPlayback(call.arguments as? [String: Any])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Now Playing

  private func setTrack(_ args: [String: Any]?) {
    guard let args = args else {
      title = ""
      artist = ""
      album = ""
      artUrl = ""
      durationMs = 0
      positionMs = 0
      positionUpdatedAt = ProcessInfo.processInfo.systemUptime
      loadedArtworkUrl = ""
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      MPNowPlayingInfoCenter.default().playbackState = .stopped
      setCommandsEnabled(false)
      return
    }
    title = args["title"] as? String ?? ""
    artist = args["artist"] as? String ?? ""
    album = args["album"] as? String ?? ""
    artUrl = args["artUrl"] as? String ?? ""
    durationMs = (args["durationMs"] as? NSNumber)?.intValue ?? 0
    positionMs = 0
    positionUpdatedAt = ProcessInfo.processInfo.systemUptime
    // 同一首歌重发元数据（引擎补全时长等）时封面不清空：已加载 / 已缓存就直接沿用，
    // 免得控制中心封面先消失再等网络请求回来
    if artUrl.isEmpty || NowPlayingArtworkStore.image(for: artUrl) == nil {
      loadedArtworkUrl = ""
    } else {
      loadedArtworkUrl = artUrl
    }
    setCommandsEnabled(true)
    updateNowPlayingInfo()
    loadArtwork()
  }

  private func setCommandsEnabled(_ enabled: Bool) {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = enabled
    commandCenter.pauseCommand.isEnabled = enabled
    commandCenter.togglePlayPauseCommand.isEnabled = enabled
    commandCenter.nextTrackCommand.isEnabled = enabled
    commandCenter.previousTrackCommand.isEnabled = enabled
    commandCenter.changePlaybackPositionCommand.isEnabled = enabled
  }

  private func setPlayback(_ args: [String: Any]?) {
    playing = args?["playing"] as? Bool ?? false
    buffering = args?["buffering"] as? Bool ?? false
    positionMs = (args?["positionMs"] as? NSNumber)?.intValue ?? 0
    positionUpdatedAt = ProcessInfo.processInfo.systemUptime

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.nextTrackCommand.isEnabled = args?["canNext"] as? Bool ?? true
    commandCenter.previousTrackCommand.isEnabled = args?["canPrevious"] as? Bool ?? true

    let center = MPNowPlayingInfoCenter.default()
    center.playbackState = buffering ? .interrupted : (playing ? .playing : .paused)
    updateNowPlayingInfo()
  }

  /// 重建 nowPlayingInfo 字典（整体赋值，系统才会增量刷新可见的元数据）。
  private func updateNowPlayingInfo() {
    let elapsed = max(0, ProcessInfo.processInfo.systemUptime - positionUpdatedAt)
    let position = Double(positionMs) / 1000.0 + ((playing && !buffering) ? elapsed : 0)
    let duration = Double(durationMs) / 1000.0
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPMediaItemPropertyAlbumTitle: album,
      MPMediaItemPropertyPlaybackDuration: Double(durationMs) / 1000.0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: duration > 0 ? min(position, duration) : position,
      // 缓冲中速率 0，系统不会继续走时
      MPNowPlayingInfoPropertyPlaybackRate: (playing && !buffering) ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if let artwork = artworkImage() {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  // MARK: - 封面

  private func artworkImage() -> MPMediaItemArtwork? {
    NowPlayingArtworkStore.image(for: loadedArtworkUrl).map { image in
      MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
  }

  /// 封面可能是 http(s) 链接，异步抓一次，匹配当前曲目后才写入。
  private func loadArtwork() {
    let url = artUrl
    guard !url.isEmpty, url != loadedArtworkUrl, let remote = URL(string: url) else { return }
    URLSession.shared.dataTask(with: remote) { data, _, _ in
      guard let data = data, let image = NSImage(data: data) else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.artUrl == url else { return }
        NowPlayingArtworkStore.store(image, for: url)
        self.loadedArtworkUrl = url
        self.updateNowPlayingInfo()
      }
    }.resume()
  }

  // MARK: - 媒体键 / 远程命令

  private func installRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    bind(commandCenter.playCommand, button: "play")
    bind(commandCenter.pauseCommand, button: "pause")
    bind(commandCenter.togglePlayPauseCommand, button: "toggle")
    bind(commandCenter.nextTrackCommand, button: "next")
    bind(commandCenter.previousTrackCommand, button: "previous")

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self = self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else { return .commandFailed }
      self.channel.invokeMethod("seek", arguments: Int(positionEvent.positionTime * 1000))
      return .success
    }
  }

  private func bind(_ command: MPRemoteCommand, button: String) {
    command.isEnabled = true
    command.addTarget { [weak self] _ in
      self?.channel.invokeMethod("button", arguments: button)
      return .success
    }
  }

  deinit {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)
  }
}

/// 封面缓存：同一 URL 只解码一次（频繁整组回写 nowPlayingInfo 时复用）。
private enum NowPlayingArtworkStore {
  private static var images: [String: NSImage] = [:]

  static func store(_ image: NSImage, for url: String) {
    if images.count > 64 { images.removeAll() }
    images[url] = image
  }

  static func image(for url: String) -> NSImage? {
    url.isEmpty ? nil : images[url]
  }
}
