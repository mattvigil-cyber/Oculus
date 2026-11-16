import AppKit
import ServiceManagement

/// Menu-bar agent: owns the server, the window, and the rules about when the
/// eye is on screen and when it is allowed to look at you.
final class AppController: NSObject, NSApplicationDelegate {

    enum Mode: String, CaseIterable {
        case off, wallpaper, screensaver, both

        var title: String {
            switch self {
            case .off:         return "Off"
            case .wallpaper:   return "Wallpaper only"
            case .screensaver: return "Screensaver only"
            case .both:        return "Wallpaper, then screensaver"
            }
        }

        /// Does this mode sit behind the icons when nothing else is happening?
        var showsWallpaper: Bool { self == .wallpaper || self == .both }

        /// Does this mode rise over everything once the machine is left alone?
        var risesWhenIdle: Bool { self == .screensaver || self == .both }
    }

    private static let pieces: [(file: String, title: String)] = [
        ("i-see-you.html", "I See You"),
        ("oculus.html",    "Ocvlvs · Speculum Verborum"),
    ]

    private var server: LocalServer!
    private var piece: Piece!
    private var window: PieceWindow!
    private var statusItem: NSStatusItem!

    private var tick: Timer?
    private var activity: NSObjectProtocol?
    private var saverShowing = false
    /// Set when the screensaver was raised by hand; suppresses dismissal until
    /// the input that raised it has settled.
    private var awaitingSettle = false
    private var manualStartedAt: Date?
    /// When the screensaver last came up. The input monitors ignore the first
    /// moment after it, so the window arriving under the pointer cannot dismiss it.
    private var risenAt: Date?
    private var lastPulseAt: Date?
    private var wakeMonitors: [Any] = []

    /// Nobody can be looking: the Mac is asleep, its displays are asleep, or
    /// the session is locked or switched out. While any of these holds the
    /// screensaver stays down and the camera stays closed. Without this the
    /// eye sat risen over a sleeping machine and the retry timer reopened the
    /// camera every 30 seconds through the night.
    private var machineAsleep = false
    private var screensAsleep = false
    private var sessionAway = false
    private var dormant: Bool { machineAsleep || screensAsleep || sessionAway }
    /// When the machine last came back. Idle time is counted from here at the
    /// earliest, so a stale reading after a wake cannot raise the eye at once.
    private var returnedAt = Date()

    // MARK: - Preferences

    private let defaults = UserDefaults.standard

    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .both }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }
    private var blinks: Bool {
        get { defaults.object(forKey: "blinks") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "blinks") }
    }
    private var pieceFile: String {
        get { defaults.string(forKey: "piece") ?? Self.pieces[0].file }
        set { defaults.set(newValue, forKey: "piece") }
    }
    private var idleMinutes: Double {
        get { defaults.object(forKey: "idleMinutes") as? Double ?? 5 }
        set { defaults.set(newValue, forKey: "idleMinutes") }
    }
    private var cameraEnabled: Bool {
        get { defaults.object(forKey: "cameraEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cameraEnabled") }
    }
    private var displayIndex: Int {
        get { defaults.integer(forKey: "displayIndex") }
        set { defaults.set(newValue, forKey: "displayIndex") }
    }
    /// 0 means whatever the display runs at.
    private var frameCap: Int {
        get { defaults.object(forKey: "frameCap") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "frameCap") }
    }

    /// Name of a file in the bundle's `web/lexicons` folder, without the
    /// extension. Empty means the piece's own vocabulary.
    private var lexicon: String {
        get { defaults.string(forKey: "lexicon") ?? "" }
        set { defaults.set(newValue, forKey: "lexicon") }
    }
    /// "single", "left" or "right". Two Macs side by side make a pair.
    private var eyeRole: String {
        get { defaults.string(forKey: "eyeRole") ?? "single" }
        set { defaults.set(newValue, forKey: "eyeRole") }
    }
    private var plateOfDay: Bool {
        get { defaults.object(forKey: "plateOfDay") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "plateOfDay") }
    }
    private var staringContest: Bool {
        get { defaults.object(forKey: "staringContest") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "staringContest") }
    }
    /// Light reflex, sleep, speech, fine text, the hour. One switch for the lot.
    private var temperament: Bool {
        get { defaults.object(forKey: "temperament") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "temperament") }
    }

    private lazy var lexicons: [String] = {
        guard let dir = Bundle.main.url(forResource: "web", withExtension: nil)?
                .appendingPathComponent("lexicons"),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    /// The query the piece reads its temperament from.
    private func pieceExtras() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !lexicon.isEmpty { items.append(URLQueryItem(name: "lex", value: lexicon)) }
        if eyeRole == "left" || eyeRole == "right" {
            items.append(URLQueryItem(name: "eye", value: eyeRole))
        }
        if plateOfDay { items.append(URLQueryItem(name: "seed", value: "today")) }
        if temperament {
            if staringContest { items.append(URLQueryItem(name: "contest", value: "1")) }
        } else {
            for key in ["light", "sleep", "duo", "contest", "speak", "micro", "circadian"] {
                items.append(URLQueryItem(name: key, value: "0"))
            }
        }
        return items
    }

    private func reloadWithExtras() {
        piece.extras = pieceExtras()
        piece.load()
        refreshMenu()
    }

    /// Index of the screen in use, or nil when the Mac has no screen attached
    /// at all. A headless or sleeping machine reached over a remote session
    /// can report zero screens, so nothing here may assume one exists.
    private var targetScreenIndex: Int? {
        let count = NSScreen.screens.count
        guard count > 0 else { return nil }
        return (0..<count).contains(displayIndex) ? displayIndex : 0
    }

    private var targetScreen: NSScreen? {
        targetScreenIndex.map { NSScreen.screens[$0] }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let web = Bundle.main.url(forResource: "web", withExtension: nil) else {
            fatal("The web resources are missing from the app bundle.")
            return
        }

        server = LocalServer(root: web)
        do {
            try server.start(preferred: 17604)
        } catch {
            fatal("Could not open a local port to serve the piece from.")
            return
        }

        piece = Piece(port: server.port, file: pieceFile, frameCap: frameCap, blinks: blinks)
        piece.extras = pieceExtras()
        window = PieceWindow(content: piece.webView)
        window.apply(role: .wallpaper, on: targetScreen)
        piece.load()

        buildStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
        // A display coming back from sleep means someone is there. Drop the
        // screensaver rather than greet them with it.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(displayWoke),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Another app coming forward earns a glance toward the pointer.
        workspace.addObserver(
            self, selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(displaySlept),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(machineWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(machineDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(sessionLeft),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(sessionCameBack),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // The lock screen has no AppKit notification of its own.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self, selector: #selector(sessionLeft),
            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(
            self, selector: #selector(sessionCameBack),
            name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)

        // Keep timers running at full rate while the eye is up, but never hold
        // the machine awake — if the display wants to sleep, let it.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Rendering the piece")

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.pulse() }
        RunLoop.main.add(t, forMode: .common)
        tick = t

        applyMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        piece?.setCameraWanted(false)
        removeWakeMonitors()
        tick?.invalidate()
        server?.stop()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    // MARK: - Mode

    private func applyMode() {
        saverShowing = false
        awaitingSettle = false
        removeWakeMonitors()
        if mode.showsWallpaper {
            window.apply(role: .wallpaper, on: targetScreen)
            window.show()
        } else {
            // Screensaver-only stays hidden until the machine is left alone;
            // off stays hidden full stop.
            window.hide()
        }
        updateCamera()
        refreshMenu()
    }

    enum Pulse { case rise, arm, sink, hold }

    /// How long input must stop before a hand-started screensaver will accept a
    /// dismissal, and the ceiling after which it arms regardless.
    static let settleIdle: TimeInterval = 2.0
    static let settleCeiling: TimeInterval = 5.0

    /// What the idle pulse should do. Pure, because this is the fiddly part:
    /// starting the screensaver by hand means clicking a menu, and a click is
    /// input, so dismissal has to stay disarmed until you have actually stopped
    /// touching the machine.
    ///
    /// `settleCeiling` is the escape hatch — keep jiggling the mouse and idle
    /// never settles, so without it a hand-started screensaver you changed your
    /// mind about could never be dismissed.
    ///
    /// `sinkWithin` is how recent input must be to count as "someone is back".
    /// It has to cover the whole gap since the previous pulse: timers run late,
    /// and a single tap that landed just after the last pulse would otherwise
    /// be more than a second old by the next one and go unnoticed.
    static func decide(showing: Bool, awaiting: Bool,
                       idle: TimeInterval, held: TimeInterval,
                       risesWhenIdle: Bool, riseAfter: TimeInterval,
                       sinkWithin: TimeInterval = 1.0) -> Pulse {
        if showing {
            if awaiting { return (idle >= settleIdle || held >= settleCeiling) ? .arm : .hold }
            return idle < sinkWithin ? .sink : .hold
        }
        return (risesWhenIdle && idle >= riseAfter) ? .rise : .hold
    }

    /// Once a second: has the machine been idle long enough to bring the eye up,
    /// or has someone come back and earned it dropping away again?
    private func pulse() {
        let now = Date()
        let sincePulse = lastPulseAt.map { now.timeIntervalSince($0) } ?? 1.0
        lastPulseAt = now
        // The gap since the last look plus a margin, bounded so a long stall
        // (the machine slept) cannot turn stale input into a dismissal.
        let sinkWithin = min(max(sincePulse + 0.25, 1.0), 5.0)

        // Asleep or locked: nothing rises, and anything still up comes down.
        if dormant {
            if saverShowing { sink() }
            return
        }

        // Keep running while it is up even in modes that never raise it
        // themselves, or a hand-started screensaver would have no way back down.
        guard mode.risesWhenIdle || saverShowing else { return }

        // For rising, idle time starts no earlier than the last wake or unlock.
        // For sinking, use the raw figure so fresh input always counts.
        let rawIdle = Self.idleSeconds()
        let idle = saverShowing ? rawIdle : min(rawIdle, now.timeIntervalSince(returnedAt))

        let held = manualStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        switch Self.decide(showing: saverShowing,
                           awaiting: awaitingSettle,
                           idle: idle,
                           held: held,
                           risesWhenIdle: mode.risesWhenIdle,
                           riseAfter: idleMinutes * 60,
                           sinkWithin: sinkWithin) {
        case .rise: rise(manual: false)
        case .arm:  awaitingSettle = false
        case .sink: sink()
        case .hold: break
        }
    }

    private func rise(manual: Bool) {
        guard !saverShowing else { return }
        saverShowing = true
        awaitingSettle = manual
        manualStartedAt = manual ? Date() : nil
        risenAt = Date()
        window.apply(role: .screensaver, on: targetScreen)
        // Fade in while the lid lifts, so it opens over the desktop.
        window.alphaValue = 0
        window.show()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            self.window.animator().alphaValue = 1
        }, completionHandler: nil)
        piece.temperament("open(1600)")
        installWakeMonitors()
        updateCamera()
    }

    private func sink() {
        guard saverShowing else { return }
        saverShowing = false
        awaitingSettle = false
        removeWakeMonitors()
        window.alphaValue = 1
        // In the combined mode it does not leave — it sinks back behind the
        // icons and carries on.
        if mode.showsWallpaper {
            window.apply(role: .wallpaper, on: targetScreen)
            window.show()
        } else {
            window.hide()
        }
        updateCamera()
        // "Start screensaver now" was disabled while it was up; give it back.
        refreshMenu()
    }

    // MARK: - Waking

    /// How long after rising the input monitors stay deaf.
    static let riseGrace: TimeInterval = 0.5

    /// Event-driven dismissal, alongside the once-a-second idle poll.
    ///
    /// The poll alone is not enough. The overlay swallows every click, so a
    /// click on it must dismiss it directly, and input arriving through a
    /// remote session should drop it at once rather than up to a second later.
    /// Mouse and scroll events need no permission. Global key events arrive
    /// only with Accessibility access; without it the idle poll covers keys.
    private func installWakeMonitors() {
        guard wakeMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel, .keyDown, .flagsChanged,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.inputArrived()
        }) {
            wakeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event -> NSEvent? in
            self?.inputArrived()
            return event
        }) {
            wakeMonitors.append(local)
        }
    }

    private func removeWakeMonitors() {
        wakeMonitors.forEach { NSEvent.removeMonitor($0) }
        wakeMonitors.removeAll()
    }

    private func inputArrived() {
        // A hand-started screensaver stays disarmed until the pulse arms it.
        guard saverShowing, !awaitingSettle else { return }
        if let risenAt, Date().timeIntervalSince(risenAt) < Self.riseGrace { return }
        sink()
    }

    @objc private func displayWoke() {
        screensAsleep = false
        cameBack()
    }

    @objc private func displaySlept() {
        screensAsleep = true
        wentAway()
    }

    @objc private func machineWillSleep() {
        machineAsleep = true
        wentAway()
    }

    @objc private func machineDidWake() {
        machineAsleep = false
        cameBack()
    }

    @objc private func sessionLeft() {
        sessionAway = true
        wentAway()
    }

    @objc private func sessionCameBack() {
        sessionAway = false
        cameBack()
    }

    /// The eye flicks toward the pointer when another app comes forward. macOS
    /// gives a third-party app no view of notification banners, so this is the
    /// nearest honest signal that something on screen just changed.
    @objc private func appActivated() {
        guard !saverShowing, !dormant, temperament, mode.showsWallpaper,
              let screen = targetScreen else { return }
        let pointer = NSEvent.mouseLocation
        let frame = screen.frame
        guard frame.contains(pointer), frame.width > 0, frame.height > 0 else { return }
        // Gaze space runs right and down. AppKit's y runs up.
        let x = Double((pointer.x - frame.midX) / (frame.width / 2))
        let y = Double(-(pointer.y - frame.midY) / (frame.height / 2))
        piece.temperament(String(format: "glance(%.3f, %.3f, 1100)", x, y))
    }

    /// Drop the screensaver and hand the camera back before the lights go out.
    private func wentAway() {
        sink()
        updateCamera()
    }

    /// Someone is there, or about to be. Never greet them with the screensaver.
    private func cameBack() {
        returnedAt = Date()
        sink()
        updateCamera()
    }

    /// A menu click proves a person is at the machine. If a wake or unlock
    /// notification ever went missing, this stops the app staying dormant.
    private func clearDormancy() {
        machineAsleep = false
        screensAsleep = false
        sessionAway = false
    }

    /// The eye watches only while it is actually on screen and not covered up.
    private func updateCamera() {
        guard cameraEnabled, !dormant else {
            piece.setCameraWanted(false)
            return
        }
        let watching: Bool
        if mode == .off {
            watching = false
        } else if saverShowing {
            // Risen over everything — nothing can be covering it.
            watching = true
        } else {
            watching = mode.showsWallpaper
                && window.isVisible
                && window.occlusionState.contains(.visible)
        }
        piece.setCameraWanted(watching)
    }

    @objc private func occlusionChanged() {
        // A full-screen window over the desktop takes the camera away with it.
        updateCamera()
    }

    @objc private func screensChanged() {
        window.apply(role: window.role, on: targetScreen)
        refreshMenu()
    }

    /// Seconds since the most recent input of any kind.
    ///
    /// Reads the combined session state as well as the hardware one. The HID
    /// state counts only devices physically attached to this Mac, so input
    /// from Screen Sharing, Chrome Remote Desktop and the like never reset it:
    /// the screensaver rose while you were working remotely and nothing you
    /// did from the far end could bring it down.
    ///
    /// `kCGAnyInputEventType` does not survive the Swift enum import, so take the
    /// minimum across the event types a person actually generates.
    private static let inputEvents: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged,
        .keyDown, .keyUp, .flagsChanged, .scrollWheel,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    private static let inputStates: [CGEventSourceStateID] = [.combinedSessionState, .hidSystemState]

    private static func idleSeconds() -> TimeInterval {
        var least = TimeInterval.greatestFiniteMagnitude
        for state in inputStates {
            for type in inputEvents {
                least = min(least, CGEventSource.secondsSinceLastEventType(state, eventType: type))
            }
        }
        return least == .greatestFiniteMagnitude ? 0 : least
    }

    // MARK: - Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Oculus")
        let menu = NSMenu()
        // We decide what is enabled; AppKit's automatic pass would just switch
        // everything with a valid target back on.
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let now = NSMenuItem(title: "Start screensaver now",
                             action: #selector(startScreensaverNow), keyEquivalent: "")
        now.target = self
        now.isEnabled = !saverShowing
        menu.addItem(now)
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for m in Mode.allCases {
            let item = NSMenuItem(title: m.title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = (m == mode) ? .on : .off
            modeMenu.addItem(item)
        }
        addSubmenu("Mode", modeMenu, to: menu)

        let pieceMenu = NSMenu()
        for p in Self.pieces {
            let item = NSMenuItem(title: p.title, action: #selector(pickPiece(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.file
            item.state = (p.file == pieceFile) ? .on : .off
            pieceMenu.addItem(item)
        }
        addSubmenu("Piece", pieceMenu, to: menu)

        let lexMenu = NSMenu()
        for name in [""] + lexicons {
            let title = name.isEmpty ? "Built in" : name.capitalized
            let item = NSMenuItem(title: title, action: #selector(pickLexicon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (name == lexicon) ? .on : .off
            lexMenu.addItem(item)
        }
        addSubmenu("Lexicon", lexMenu, to: menu)

        let eyeMenu = NSMenu()
        for (raw, title) in [("single", "Single eye"), ("left", "Left of a pair"), ("right", "Right of a pair")] {
            let item = NSMenuItem(title: title, action: #selector(pickEye(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = raw
            item.state = (raw == eyeRole) ? .on : .off
            eyeMenu.addItem(item)
        }
        addSubmenu("Eye", eyeMenu, to: menu)

        let screenMenu = NSMenu()
        for (i, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName
            let size = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            let item = NSMenuItem(title: "\(name) — \(size)", action: #selector(pickDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == targetScreenIndex) ? .on : .off
            screenMenu.addItem(item)
        }
        addSubmenu("Display", screenMenu, to: menu)

        let idleMenu = NSMenu()
        for minutes in [1.0, 2.0, 5.0, 10.0, 15.0] {
            let item = NSMenuItem(title: "\(Int(minutes)) min", action: #selector(pickIdle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.state = (minutes == idleMinutes) ? .on : .off
            idleMenu.addItem(item)
        }
        let idleItem = addSubmenu("Rises after", idleMenu, to: menu)
        idleItem.isEnabled = mode.risesWhenIdle

        // A requestAnimationFrame throttle can only deliver divisors of the
        // refresh rate, so 60 on a 144 Hz panel is really 48. Say so rather than
        // quietly hand over a number nobody asked for.
        let refresh = max(targetScreen?.maximumFramesPerSecond ?? 60, 1)
        let fpsMenu = NSMenu()
        for fps in [24, 30, 60, 0] {
            let label: String
            if fps == 0 {
                label = "Display rate — \(refresh) fps"
            } else {
                let actual = refresh / max(1, Int((Double(refresh) / Double(fps)).rounded(.up)))
                label = actual == fps ? "Up to \(fps) fps" : "Up to \(fps) fps — \(actual) here"
            }
            let item = NSMenuItem(title: label, action: #selector(pickFrameCap(_:)), keyEquivalent: "")
            item.target = self
            item.tag = fps
            item.state = (fps == frameCap) ? .on : .off
            fpsMenu.addItem(item)
        }
        addSubmenu("Frame rate", fpsMenu, to: menu)

        menu.addItem(.separator())

        let watch = NSMenuItem(title: "Let it watch me", action: #selector(toggleCamera), keyEquivalent: "")
        watch.target = self
        watch.state = cameraEnabled ? .on : .off
        menu.addItem(watch)

        let blink = NSMenuItem(title: "Let it blink", action: #selector(toggleBlink), keyEquivalent: "")
        blink.target = self
        blink.state = blinks ? .on : .off
        menu.addItem(blink)

        let mood = NSMenuItem(title: "Temperament", action: #selector(toggleTemperament), keyEquivalent: "")
        mood.target = self
        mood.state = temperament ? .on : .off
        menu.addItem(mood)

        let contest = NSMenuItem(title: "Staring contest", action: #selector(toggleContest), keyEquivalent: "")
        contest.target = self
        contest.state = (temperament && staringContest) ? .on : .off
        contest.isEnabled = temperament
        menu.addItem(contest)

        let daily = NSMenuItem(title: "Plate of the day", action: #selector(togglePlateOfDay), keyEquivalent: "")
        daily.target = self
        daily.state = plateOfDay ? .on : .off
        menu.addItem(daily)

        let reload = NSMenuItem(title: "Reload piece", action: #selector(reloadPiece), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
            login.target = self
            login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(login)
        }

        let quit = NSMenuItem(title: "Quit Oculus", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @discardableResult
    private func addSubmenu(_ title: String, _ submenu: NSMenu, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    /// Raise it deliberately and walk away, without waiting out the idle timer.
    @objc private func startScreensaverNow() {
        clearDormancy()
        rise(manual: true)
        refreshMenu()
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = Mode(rawValue: raw) else { return }
        mode = m
        clearDormancy()
        applyMode()
    }

    @objc private func pickPiece(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String, file != pieceFile else { return }
        pieceFile = file
        piece.load(file: file)
        refreshMenu()
    }

    @objc private func pickLexicon(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, name != lexicon else { return }
        lexicon = name
        reloadWithExtras()
    }

    @objc private func pickEye(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, raw != eyeRole else { return }
        eyeRole = raw
        reloadWithExtras()
    }

    @objc private func toggleTemperament() {
        temperament.toggle()
        reloadWithExtras()
    }

    @objc private func toggleContest() {
        staringContest.toggle()
        reloadWithExtras()
    }

    @objc private func togglePlateOfDay() {
        plateOfDay.toggle()
        reloadWithExtras()
    }

    @objc private func pickDisplay(_ sender: NSMenuItem) {
        displayIndex = sender.tag
        window.apply(role: window.role, on: targetScreen)
        refreshMenu()
    }

    @objc private func pickIdle(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Double else { return }
        idleMinutes = minutes
        refreshMenu()
    }

    @objc private func pickFrameCap(_ sender: NSMenuItem) {
        frameCap = sender.tag
        piece.setFrameCap(sender.tag)
        refreshMenu()
    }

    @objc private func toggleCamera() {
        cameraEnabled.toggle()
        updateCamera()
        refreshMenu()
    }

    @objc private func toggleBlink() {
        blinks.toggle()
        piece.setBlinks(blinks)
        refreshMenu()
    }

    @objc private func reloadPiece() {
        piece.load()
    }

    @available(macOS 13.0, *)
    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        refreshMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func fatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Oculus cannot start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
