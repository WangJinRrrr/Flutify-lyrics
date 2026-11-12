import Cocoa

@main
enum TitlebarTest {
  static func drain() {
    let deadline = Date(timeIntervalSinceNow: 0.2)
    while Date() < deadline {
      if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.01),
                                    inMode: .default, dequeue: true) {
        NSApp.sendEvent(event)
      }
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }

  static func verify(_ window: NSWindow, _ label: String) {
    let root = window.contentView!.superview!
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      let button = window.standardWindowButton(kind)!
      let rect = button.convert(button.bounds, to: nil)
      precondition(abs(window.frame.height - rect.midY - 28) < 0.5, "\(label): vertical alignment")
      for fraction: CGFloat in [0.2, 0.5, 0.8] {
        let point = NSPoint(x: rect.midX, y: rect.minY + rect.height * fraction)
        let hit = root.hitTest(root.convert(point, from: nil))
        precondition(hit === button || hit?.isDescendant(of: button) == true,
                     "\(label): button \(kind) misses at \(point), hit=\(String(describing: hit))")
      }
    }
    let point = NSPoint(x: 250, y: window.frame.height - 28)
    let hit = root.hitTest(root.convert(point, from: nil))
    precondition(hit === window.contentView || hit?.isDescendant(of: window.contentView!) == true,
                 "\(label): enlarged titlebar intercepts Flutter controls")
    print("PASS: \(label)")
  }

  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    let aligner = TrafficLightAligner(window: window)
    // Match window_manager: titlebar setup happens after the runner is created.
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.makeKeyAndOrderFront(nil)
    drain()
    verify(window, "startup")
    for width: CGFloat in [360, 1360, 800, 900] {
      window.setContentSize(NSSize(width: width, height: 700))
      drain()
      verify(window, "resize \(width)")
    }
    // Exercise repeated notifications to detect cumulative coordinate drift.
    for _ in 0..<3 {
      NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
      drain()
      verify(window, "realignment")
    }
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.toggleFullScreen(nil)
    var deadline = Date(timeIntervalSinceNow: 10)
    while !window.styleMask.contains(.fullScreen) && Date() < deadline { drain() }
    precondition(window.styleMask.contains(.fullScreen), "failed to enter native fullscreen")
    for _ in 0..<10 { drain() }
    window.toggleFullScreen(nil)
    deadline = Date(timeIntervalSinceNow: 10)
    while window.styleMask.contains(.fullScreen) && Date() < deadline { drain() }
    precondition(!window.styleMask.contains(.fullScreen), "failed to exit native fullscreen")
    for _ in 0..<10 { drain() }
    verify(window, "native fullscreen round trip")
    withExtendedLifetime(aligner) { window.close() }
  }
}
