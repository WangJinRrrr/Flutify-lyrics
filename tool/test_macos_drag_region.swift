import Cocoa
import ObjectiveC

// Compile with:
// swiftc -target "$(uname -m)-apple-macos12.0" \
//   macos/Runner/TrafficLightAligner.swift tool/test_macos_drag_region.swift \
//   -o /tmp/flutify-drag-region-test
//
// Default (production): use TrafficLightAligner's real configuration and fail if
// AppKit treats a search-box point as an implicit drag, including after resize
// and a native fullscreen round trip in the test's own window.
// --diagnose: inspect baseline, isMovable=false, and a narrowed titlebar.
// --screen-recovery-only: test display-change recovery without fullscreen or the
// private AppKit drag predicate (useful for a focused old/new-code comparison).
// --interactive --mode=production: real Window Server test using a physical mouse.
// Process-targeted synthetic drags can bypass Window Server even in baseline
// mode, so they must not be used as proof that native window movement works.
// Other modes: production, baseline, narrow. Baseline explicitly reenables native
// dragging for a red control. Drag blue (search) and orange (explicit drag).
//
// This test never posts global input events or touches other apps. The optional
// AppKit selector is PRIVATE and read-only; it is intentionally restricted to
// this standalone diagnostic, never production code. Unsupported runtimes exit
// 78 rather than silently claiming a pass. A predicate test is not a substitute
// for the interactive check that explicit performDrag actually moves a window.

private final class NativeDragTestWindow: NSWindow {
  // Normal programmatic placement is constrained by AppKit. Temporarily bypass
  // only that placement step to reproduce the geometry left by a removed screen;
  // use normal NSWindow behavior again before exercising the production observer.
  var permitsOffscreenTestPlacement = false

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    permitsOffscreenTestPlacement ? frameRect : super.constrainFrameRect(frameRect, to: screen)
  }
}

private final class FlutterLikeView: NSView {
  var mode = "production"
  override var isOpaque: Bool { true }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    NSColor.systemBlue.withAlphaComponent(0.35).setFill()
    NSRect(x: 230, y: 10, width: 350, height: 36).fill()
    NSColor.systemOrange.withAlphaComponent(0.4).setFill()
    NSRect(x: 620, y: 10, width: 250, height: 36).fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor,
    ]
    for (text, point) in [
      ("SEARCH: must not move", NSPoint(x: 245, y: 18)),
      ("EXPLICIT performDrag", NSPoint(x: 635, y: 18)),
      ("Flutify Drag Probe — \(mode)", NSPoint(x: 30, y: 100)),
      ("Drag inside BLUE, then ORANGE. Frame changes print to terminal.", NSPoint(x: 30, y: 135)),
      ("Blue matches Flutter: opaque NSView, no native NSTextField.", NSPoint(x: 30, y: 165)),
      ("Orange explicitly invokes NSWindow.performDrag(with:).", NSPoint(x: 30, y: 195)),
    ] {
      (text as NSString).draw(at: point, withAttributes: attributes)
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    print("CONTENT mouseDown at \(point); native mouseDownCanMoveWindow=\(mouseDownCanMoveWindow)")
    if NSRect(x: 620, y: 10, width: 250, height: 36).contains(point), let window {
      print("EXPLICIT performDrag requested; isMovable=\(window.isMovable)")
      window.performDrag(with: event)
      print("EXPLICIT performDrag returned; isMovable=\(window.isMovable)")
    }
  }

  override func mouseDragged(with event: NSEvent) {
    print("CONTENT mouseDragged at \(convert(event.locationInWindow, from: nil))")
  }
}

@main
enum DragRegionTest {
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

  static func shouldStartDrag(_ window: NSWindow, at point: NSPoint) -> Bool {
    let selector = NSSelectorFromString("_shouldStartWindowDragForEvent:")
    guard let method = class_getInstanceMethod(type(of: window), selector),
          let encoding = method_getTypeEncoding(method),
          String(cString: encoding) == "B24@0:8@16" else {
      fputs("UNSUPPORTED: AppKit drag-decision diagnostic unavailable\n", stderr)
      exit(78)
    }
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    typealias Decision = @convention(c) (AnyObject, Selector, NSEvent) -> Bool
    let implementation = unsafeBitCast(method_getImplementation(method), to: Decision.self)
    return implementation(window, selector, event)
  }

  static func inspect(_ window: NSWindow, _ label: String) -> Int {
    let root = window.contentView!.superview!
    var failures = 0
    print("\(label): isMovable=\(window.isMovable), background=\(window.isMovableByWindowBackground)")
    for fromTop: CGFloat in [12, 20, 28, 36, 44] {
      let point = NSPoint(x: 350, y: window.frame.height - fromTop)
      let hit = root.hitTest(root.convert(point, from: nil))
      let drag = shouldStartDrag(window, at: point)
      let contentHit = hit === window.contentView || hit?.isDescendant(of: window.contentView!) == true
      print("  search top=\(fromTop): contentHit=\(contentHit), AppKitDrag=\(drag)")
      if !contentHit || drag { failures += 1 }
    }
    return failures
  }

  static func narrowTitlebar(_ window: NSWindow) {
    let frameView = window.contentView!.superview!
    var ancestor = window.standardWindowButton(.closeButton)?.superview
    while let view = ancestor, view !== frameView {
      var frame = view.frame
      frame.size.width = 120
      view.frame = frame
      ancestor = view.superview
    }
  }

  static func verifyLifecycle(_ window: NSWindow) -> Int {
    var failures = 0
    for width: CGFloat in [800, 1360] {
      window.setContentSize(NSSize(width: width, height: 420))
      drain()
      failures += inspect(window, "production after resize \(width)")
    }
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.toggleFullScreen(nil)
    var deadline = Date(timeIntervalSinceNow: 10)
    while !window.styleMask.contains(.fullScreen) && Date() < deadline { drain() }
    guard window.styleMask.contains(.fullScreen) else {
      fputs("FAIL: test window did not enter native fullscreen\n", stderr)
      return failures + 1
    }
    for _ in 0..<10 { drain() }
    window.toggleFullScreen(nil)
    deadline = Date(timeIntervalSinceNow: 10)
    while window.styleMask.contains(.fullScreen) && Date() < deadline { drain() }
    guard !window.styleMask.contains(.fullScreen) else {
      fputs("FAIL: test window did not exit native fullscreen\n", stderr)
      return failures + 1
    }
    for _ in 0..<10 { drain() }
    return failures + inspect(window, "production after native fullscreen round trip")
  }

  static func titlebarIsReachable(_ window: NSWindow) -> Bool {
    let frame = window.frame
    let bar = NSRect(x: frame.minX, y: frame.maxY - 56, width: frame.width, height: 56)
    return NSScreen.screens.contains { $0.visibleFrame.intersects(bar) }
  }

  private static func verifyScreenRecovery(_ window: NativeDragTestWindow) -> Int {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      fputs("FAIL: display-change test requires an attached screen\n", stderr)
      return 1
    }
    var failures = 0
    let originalFrame = window.frame
    defer {
      window.permitsOffscreenTestPlacement = false
      window.setFrame(originalFrame, display: false)
    }
    // A display notification alone must not move or resize an accessible window.
    window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 20,
                                  y: screen.visibleFrame.maxY - window.frame.height - 20))
    drain()
    let reachableFrame = window.frame
    guard titlebarIsReachable(window) else {
      fputs("FAIL: could not position the test window on an attached screen\n", stderr)
      return 1
    }
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                    object: NSApp)
    drain()
    if window.frame != reachableFrame {
      fputs("FAIL: display notification moved/resized an already reachable window\n", stderr)
      failures += 1
    } else {
      print("PASS: display notification preserves reachable window position and size")
    }

    // Simulate a window stranded on a removed monitor without reconfiguring any
    // real display: move only this test's window outside the union of all screens.
    let screens = NSScreen.screens.map(\.frame)
    let outsideX = (screens.map(\.maxX).max() ?? 0) + window.frame.width + 1000
    let outsideY = (screens.map(\.minY).min() ?? 0) - window.frame.height - 1000
    window.permitsOffscreenTestPlacement = true
    window.setFrameOrigin(NSPoint(x: outsideX, y: outsideY))
    drain()
    window.permitsOffscreenTestPlacement = false
    guard !titlebarIsReachable(window) else {
      fputs("FAIL: offscreen test setup was constrained back onto a screen\n", stderr)
      return failures + 1
    }
    let strandedSize = window.frame.size
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                    object: NSApp)
    drain()
    if !titlebarIsReachable(window) {
      fputs("FAIL: display change left the window's entire titlebar offscreen\n", stderr)
      failures += 1
    } else if window.frame.size != strandedSize {
      fputs("FAIL: recovering an offscreen titlebar changed the window size\n", stderr)
      failures += 1
    } else {
      print("PASS: display change restores the offscreen titlebar without resizing")
    }
    return failures
  }

  static func main() {
    setbuf(stdout, nil)
    let arguments = CommandLine.arguments
    let interactive = arguments.contains("--interactive")
    let diagnose = arguments.contains("--diagnose")
    let screenRecoveryOnly = arguments.contains("--screen-recovery-only")
    let mode = arguments.first(where: { $0.hasPrefix("--mode=") })?
      .replacingOccurrences(of: "--mode=", with: "") ?? "production"
    guard ["production", "baseline", "immovable", "narrow"].contains(mode) else {
      fputs("Unknown mode. Use production, baseline, immovable, or narrow.\n", stderr)
      exit(64)
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(interactive ? .regular : .accessory)
    NSApp.finishLaunching()
    let window = NativeDragTestWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 420),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Flutify Drag Probe [\(mode)]"
    window.isReleasedWhenClosed = false
    let content = FlutterLikeView(frame: NSRect(x: 0, y: 0, width: 900, height: 420))
    content.mode = mode
    window.contentView = content
    let aligner = TrafficLightAligner(window: window)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.orderFront(nil)
    drain()
    if mode == "baseline" || mode == "narrow" || diagnose { window.isMovable = true }
    if mode == "immovable" { window.isMovable = false }
    if mode == "narrow" { narrowTitlebar(window) }
    var failures = screenRecoveryOnly ? 0 : inspect(window, diagnose ? "baseline" : mode)
    if screenRecoveryOnly && !interactive && !diagnose {
      failures += verifyScreenRecovery(window)
    } else if mode == "production" && !interactive && !diagnose {
      failures += verifyLifecycle(window)
      failures += verifyScreenRecovery(window)
    }

    if diagnose {
      window.isMovable = false
      drain()
      _ = inspect(window, "isMovable=false")
      window.isMovable = true
      narrowTitlebar(window)
      drain()
      _ = inspect(window, "narrow titlebar")
      failures = 0
    }

    if interactive {
      let menuBar = NSMenu()
      let appItem = NSMenuItem()
      appItem.submenu = NSMenu()
      appItem.submenu?.addItem(withTitle: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
      menuBar.addItem(appItem)
      let windowItem = NSMenuItem()
      let windowMenu = NSMenu(title: "Window")
      let fullscreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
      fullscreen.target = window
      fullscreen.keyEquivalentModifierMask = [.control, .command]
      windowMenu.addItem(fullscreen)
      windowItem.submenu = windowMenu
      menuBar.addItem(windowItem)
      NSApp.mainMenu = menuBar
      var previousFrame = window.frame
      let observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
        object: window, queue: .main) { _ in
          let frame = window.frame
          if frame.origin != previousFrame.origin {
            print("WINDOW MOVED delta=(\(frame.minX - previousFrame.minX), \(frame.minY - previousFrame.minY)) frame=\(frame)")
          }
          previousFrame = frame
        }
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      print("READY: pid=\(ProcessInfo.processInfo.processIdentifier), title=\(window.title), frame=\(window.frame)")
      print("Search center in window: (405, \(window.frame.height - 28)); explicit: (745, \(window.frame.height - 28))")
      print("Use a physical mouse for Window Server validation; this test synthesizes no global input.")
      withExtendedLifetime((aligner, observer)) { NSApp.run() }
    } else {
      withExtendedLifetime(aligner) { window.close() }
      if failures > 0 {
        fputs("FAIL: native titlebar regression checks failed\n", stderr)
        exit(1)
      }
      print(diagnose ? "Diagnostic complete (not a pass/fail run)." : "PASS: native titlebar regression checks")
    }
  }
}
