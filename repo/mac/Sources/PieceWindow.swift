import AppKit

/// One window, reconfigured between roles.
///
/// Wallpaper and screensaver differ only in window level, whether they swallow
/// input, and when they are on screen — so reusing a single window keeps the
/// WKWebView alive across a mode switch instead of reloading the piece.
final class PieceWindow: NSWindow {

    enum Role {
        /// Behind the icons, above the desktop picture. Never takes input.
        case wallpaper
        /// Above everything, including the menu bar. Takes input only to dismiss.
        case screensaver
    }

    private(set) var role: Role = .wallpaper

    override var canBecomeKey: Bool { role == .screensaver }
    override var canBecomeMain: Bool { false }

    init(content: NSView) {
        super.init(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1600, height: 900),
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        isReleasedWhenClosed = false
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        displaysWhenScreenProfileChanges = true
        contentView = content
        content.frame = contentView?.bounds ?? .zero
    }

    /// `screen` is nil when the Mac has no display attached; the role still
    /// applies and the frame is left for the next screen change to correct.
    func apply(role: Role, on screen: NSScreen?) {
        self.role = role

        switch role {
        case .wallpaper:
            // Just under the desktop icons — the slot live wallpapers occupy.
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            ignoresMouseEvents = true
            acceptsMouseMovedEvents = false

        case .screensaver:
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            ignoresMouseEvents = false
            // So a pointer move over the overlay reaches the dismissal monitor.
            acceptsMouseMovedEvents = true
        }

        if let screen { setFrame(screen.frame, display: true) }
    }

    func show() {
        // Never activate the app — the wallpaper must not steal focus, and the
        // screensaver overlay only needs to be visible, not frontmost in the Dock.
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
