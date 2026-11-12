import Cocoa

/// Keep the native buttons and their hit-test ancestors inside the 56pt Flutter bar.
final class TrafficLightAligner {
  private weak var window: NSWindow?
  private var observers: [NSObjectProtocol] = []
  private var pending = false
  private var transitioning = false
  private static let barHeight: CGFloat = 56
  private static let leftInset: CGFloat = 21

  init(window: NSWindow) {
    self.window = window
    // AppKit's server-side titlebar drag runs before Flutter hit testing and
    // otherwise steals mouse selection in the search field's upper half.
    // WindowDragArea still explicitly starts drags via performDrag(with:).
    window.isMovable = false
    let center = NotificationCenter.default
    for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                 NSWindow.didExitFullScreenNotification] {
      observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        if name == NSWindow.didExitFullScreenNotification { self?.transitioning = false }
        self?.schedule()
      })
    }
    for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
      observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        self?.transitioning = true
      })
    }
    // AppKit also stops relocating non-movable windows after display changes.
    observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                         object: nil, queue: .main) { [weak self] _ in
      self?.restoreVisibleTitlebar()
    })
    schedule()
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  private func restoreVisibleTitlebar() {
    guard let window = window, !window.styleMask.contains(.fullScreen),
          let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let frame = window.frame
    let titlebar = NSRect(x: frame.minX, y: frame.maxY - Self.barHeight,
                         width: frame.width, height: Self.barHeight)
    guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(titlebar) }) else { return }
    let visible = screen.visibleFrame
    window.setFrameOrigin(NSPoint(x: visible.minX + max(0, (visible.width - frame.width) / 2),
                                  y: visible.maxY - frame.height))
  }

  private func schedule() {
    guard !pending else { return }
    pending = true
    // AppKit and window_manager must finish their titlebar layout first.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.pending = false
      self.apply()
    }
  }

  private func apply() {
    guard let window = window, !transitioning, !window.styleMask.contains(.fullScreen),
          let close = window.standardWindowButton(.closeButton),
          let mini = window.standardWindowButton(.miniaturizeButton),
          let zoom = window.standardWindowButton(.zoomButton),
          let parent = close.superview,
          let frameView = window.contentView?.superview
    else { return }

    // Moving just the buttons below a standard 22/28pt titlebar leaves part of
    // their visible area outside NSView.hitTest. Enlarge every titlebar ancestor,
    // keeping its top edge fixed, before positioning the buttons.
    var ancestors: [NSView] = []
    var view: NSView? = parent
    while let current = view, current !== frameView {
      ancestors.append(current)
      view = current.superview
    }
    guard view === frameView else { return }
    for ancestor in ancestors.reversed() {
      guard let superview = ancestor.superview else { continue }
      var frame = ancestor.frame
      if frame.height < Self.barHeight {
        if !superview.isFlipped { frame.origin.y -= Self.barHeight - frame.height }
        frame.size.height = Self.barHeight
        ancestor.frame = frame
      }
    }

    let closeInWindow = parent.convert(close.frame, to: nil)
    let deltaX = Self.leftInset - closeInWindow.minX
    let targetY = window.frame.height - Self.barHeight / 2
    for button in [close, mini, zoom] {
      guard let container = button.superview else { continue }
      let frame = container.convert(button.frame, to: nil)
      let target = NSRect(x: frame.minX + deltaX, y: targetY - frame.height / 2,
                          width: frame.width, height: frame.height)
      button.frame = container.convert(target, from: nil)
    }
  }
}
