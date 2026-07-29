import Cocoa
import ServiceManagement

// AwakeToggle — a menu-bar controller for `pmset -a disablesleep`.
// Click the icon to choose ON, AUTO (while Codex is working), or OFF.
// This local build uses a narrowly scoped passwordless-sudo rule for pmset,
// allowing the menu-bar toggle to work without an authorization dialog.

// MARK: - Localization

// Read from the system language list rather than the bundle: this app ships as a
// hand-assembled bundle with no .lproj resources, so Bundle.preferredLocalizations
// would always report the development region.
enum Lang { case en, zh, fr }

let lang: Lang = {
    guard let code = Locale.preferredLanguages.first else { return .en }
    if code.hasPrefix("zh") { return .zh }
    if code.hasPrefix("fr") { return .fr }
    return .en
}()

func t(_ en: String, _ zh: String, _ fr: String) -> String {
    switch lang {
    case .en: return en
    case .zh: return zh
    case .fr: return fr
    }
}

enum S {
    static let title = t("Keep Awake", "保持在线常驻", "Rester éveillé")
    static let subtitle = t("Choose when macOS may sleep",
                            "选择何时允许 macOS 休眠",
                            "Choisir quand macOS peut se mettre en veille")
    static let hint = t("Click the menu-bar icon to change mode",
                        "点击菜单栏图标以更改模式",
                        "Cliquez sur l'icône pour changer de mode")
    static let quit = t("Quit", "退出", "Quitter")
    static let on = t("ON", "开启", "ACTIF")
    static let auto = t("AUTO", "自动", "AUTO")
    static let off = t("OFF", "关闭", "INACTIF")
    static let launchTitle = t("Launch on Login", "登录时启动", "Ouvrir à la connexion")
    static let launchSubtitle = t("Start automatically",
                                  "自动启动",
                                  "Démarrer automatiquement")
    static let launchApproval = t("Approval required in System Settings",
                                  "需要在系统设置中批准",
                                  "Approbation requise dans Réglages Système")
    static let launchUnavailable = t("Requires macOS 13 or later",
                                     "需要 macOS 13 或更高版本",
                                     "Nécessite macOS 13 ou une version ultérieure")

    static let alwaysAwake = t("Always preventing sleep",
                               "始终阻止休眠",
                               "Veille toujours désactivée")
    static let normalSleep = t("Normal macOS sleep",
                               "正常 macOS 休眠",
                               "Veille macOS normale")
    static let autoIdle = t("AUTO · No active Codex tasks",
                            "自动 · 没有活动的 Codex 任务",
                            "AUTO · Aucune tâche Codex active")
    static let autoConnecting = t("AUTO · Connecting to Codex",
                                  "自动 · 正在连接 Codex",
                                  "AUTO · Connexion à Codex")
    static let autoUnavailable = t("AUTO · Codex status unavailable",
                                   "自动 · Codex 状态不可用",
                                   "AUTO · État Codex indisponible")

    static func autoActive(_ count: Int) -> String {
        t("AUTO · \(count) active Codex task\(count == 1 ? "" : "s")",
          "自动 · \(count) 个活动的 Codex 任务",
          "AUTO · \(count) tâche\(count == 1 ? "" : "s") Codex active\(count == 1 ? "" : "s")")
    }

    static func tooltip(mode: AwakeMode,
                        actualOn: Bool,
                        activity: CodexActivityState) -> String {
        switch mode {
        case .on:
            return t("Keep Awake: ON — always preventing sleep",
                     "常驻在线：开启 — 始终阻止休眠",
                     "Rester éveillé : ACTIF — veille toujours désactivée")
        case .auto:
            switch activity.availability {
            case .connecting:
                return autoConnecting
            case .unavailable:
                return autoUnavailable
            case .available:
                return activity.activeCount > 0
                    ? autoActive(activity.activeCount)
                    : autoIdle
            }
        case .off:
            return t("Keep Awake: OFF — normal sleep",
                     "常驻在线：关闭 — 正常休眠",
                     "Rester éveillé : INACTIF — veille normale")
        }
    }
}

enum AwakeMode: String {
    case on
    case auto
    case off

    var segment: Int {
        switch self {
        case .on: return 0
        case .auto: return 1
        case .off: return 2
        }
    }

    init?(segment: Int) {
        switch segment {
        case 0: self = .on
        case 1: self = .auto
        case 2: self = .off
        default: return nil
        }
    }
}

// MARK: - Icons

// A laptop seen edge-on: hinge at the back-right, front lip to the left.
// closed == true  -> lid resting on the base: always-on is ACTIVE, the lid can
//                    shut without the machine sleeping.
// closed == false -> lid cracked open: normal power behaviour.
// Draws the glyph on an 18x18 grid into the current context, using whatever
// stroke colour the caller set. Kept separate from laptopIcon so the same
// geometry can be re-rendered at any scale (the website thumbnail does this)
// without the two drifting apart.
func drawLaptop(closed: Bool, lineWidth lw: CGFloat = 1.1) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    if closed {
        let slab = NSBezierPath(roundedRect: NSRect(x: 1.8, y: 6.4, width: 14.4, height: 5.2),
                                xRadius: 1.3, yRadius: 1.3)
        slab.lineWidth = lw
        slab.stroke()
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: 1.8, y: 9.0))
        seam.line(to: NSPoint(x: 16.2, y: 9.0))
        seam.lineWidth = lw * 0.85
        seam.stroke()
    } else {
        let base = NSBezierPath(roundedRect: NSRect(x: 1.8, y: 4.6, width: 14.4, height: 2.4),
                                xRadius: 0.9, yRadius: 0.9)
        base.lineWidth = lw
        base.stroke()
        ctx.saveGState()
        ctx.translateBy(x: 15.4, y: 7.0)
        ctx.rotate(by: 150 * .pi / 180)   // lid cracked 30° off the deck
        let lid = NSBezierPath(roundedRect: NSRect(x: 0, y: -2.6, width: 11.4, height: 2.6),
                               xRadius: 0.9, yRadius: 0.9)
        lid.lineWidth = lw
        lid.stroke()
        ctx.restoreGState()
    }
}

func laptopIcon(closed: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18))
    img.lockFocus()
    NSColor.black.setStroke()
    drawLaptop(closed: closed)
    img.unlockFocus()
    img.isTemplate = true
    return img
}

// MARK: - Switch row shown inside the menu

final class ModeControl: NSSegmentedControl {
    private let selectedColors: [NSColor]

    init(labels: [String],
         selectedColors: [NSColor],
         initialSegment: Int) {
        self.selectedColors = selectedColors
        super.init(frame: .zero)
        segmentCount = labels.count
        trackingMode = .selectOne
        for (index, label) in labels.enumerated() {
            setLabel(label, forSegment: index)
        }
        selectedSegment = initialSegment
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let background = NSBezierPath(roundedRect: outer, xRadius: 6, yRadius: 6)
        NSColor.quaternaryLabelColor.setFill()
        background.fill()

        let segmentWidth = outer.width / CGFloat(segmentCount)
        let selected = NSRect(x: outer.minX + CGFloat(selectedSegment) * segmentWidth,
                              y: outer.minY,
                              width: segmentWidth,
                              height: outer.height)
        let selectedPath = NSBezierPath(roundedRect: selected.insetBy(dx: 1, dy: 1),
                                        xRadius: 5,
                                        yRadius: 5)
        let defaultSelectedColor = selectedColors.indices.contains(selectedSegment)
            ? selectedColors[selectedSegment]
            : NSColor.systemGray
        defaultSelectedColor.withAlphaComponent(isEnabled ? 1 : 0.45).setFill()
        selectedPath.fill()

        let font = NSFont.boldSystemFont(ofSize: 10)
        for index in 0..<segmentCount {
            let label = label(forSegment: index) ?? ""
            let color = index == selectedSegment
                ? NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.65)
                : NSColor.labelColor.withAlphaComponent(isEnabled ? 1 : 0.45)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            let x = outer.minX + CGFloat(index) * segmentWidth
                + (segmentWidth - size.width) / 2
            let y = outer.midY - size.height / 2
            (label as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }

        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

final class ModeRow: NSView {
    let modeControl = ModeControl(labels: [S.on, S.auto, S.off],
                                  selectedColors: [.systemBlue, .systemBlue, .systemGray],
                                  initialSegment: AwakeMode.off.segment)
    let title = NSTextField(labelWithString: S.title)
    let subtitle = NSTextField(labelWithString: S.subtitle)

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        title.font = .menuFont(ofSize: 13)
        subtitle.font = .menuFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        modeControl.target = target
        modeControl.action = action

        let textWidth: CGFloat = 235
        let padding: CGFloat = 14
        let gap: CGFloat = 20
        let controlWidth: CGFloat = 174

        frame = NSRect(x: 0, y: 0,
                       width: padding + textWidth + gap + controlWidth + padding,
                       height: 54)
        title.frame = NSRect(x: padding, y: 29, width: textWidth, height: 16)
        subtitle.frame = NSRect(x: padding, y: 10, width: textWidth, height: 15)
        modeControl.frame = NSRect(x: padding + textWidth + gap, y: 15,
                                   width: controlWidth, height: 25)

        addSubview(title)
        addSubview(subtitle)
        addSubview(modeControl)
    }

    func update(mode: AwakeMode, activity: CodexActivityState) {
        modeControl.selectedSegment = mode.segment
        modeControl.needsDisplay = true
        switch mode {
        case .on:
            subtitle.stringValue = S.alwaysAwake
        case .auto:
            switch activity.availability {
            case .connecting:
                subtitle.stringValue = S.autoConnecting
            case .unavailable:
                subtitle.stringValue = S.autoUnavailable
            case .available where activity.activeCount > 0:
                subtitle.stringValue = S.autoActive(activity.activeCount)
            case .available:
                subtitle.stringValue = S.autoIdle
            }
        case .off:
            subtitle.stringValue = S.normalSleep
        }
        subtitle.textColor = .secondaryLabelColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

final class LoginRow: NSView {
    let modeControl = ModeControl(labels: [S.on, S.off],
                                  selectedColors: [.systemBlue, .systemGray],
                                  initialSegment: 1)
    let title = NSTextField(labelWithString: S.launchTitle)
    let subtitle = NSTextField(labelWithString: S.launchSubtitle)

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        title.font = .menuFont(ofSize: 13)
        subtitle.font = .menuFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        modeControl.target = target
        modeControl.action = action

        let textWidth: CGFloat = 235
        let padding: CGFloat = 14
        let gap: CGFloat = 20
        let controlWidth: CGFloat = 174

        frame = NSRect(x: 0, y: 0,
                       width: padding + textWidth + gap + controlWidth + padding,
                       height: 54)
        title.frame = NSRect(x: padding, y: 29, width: textWidth, height: 16)
        subtitle.frame = NSRect(x: padding, y: 10, width: textWidth, height: 15)
        modeControl.frame = NSRect(x: padding + textWidth + gap, y: 15,
                                   width: controlWidth, height: 25)

        addSubview(title)
        addSubview(subtitle)
        addSubview(modeControl)
    }

    func update(on: Bool,
                subtitle text: String = S.launchSubtitle) {
        modeControl.selectedSegment = on ? 0 : 1
        modeControl.needsDisplay = true
        subtitle.stringValue = text
        subtitle.textColor = .secondaryLabelColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let modeDefaultsKey = "AwakeMode"
    private let idleGraceSeconds: TimeInterval = 10

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let iconClosed = laptopIcon(closed: true)
    let iconOpen = laptopIcon(closed: false)
    var menu: NSMenu!
    var modeRow: ModeRow!
    var loginRow: LoginRow!
    var awakeMode = AwakeMode.off
    var monitorTimer: Timer?
    var codexActivity = CodexActivityState.connecting
    var lastActiveCount = 0
    var idleGraceDeadline: Date?
    let systemSleepAssertion = SystemSleepAssertion()
    let clamshellDisplaySleepController = ClamshellDisplaySleepController()
    lazy var codexMonitor = CodexIPCMonitor { [weak self] activity in
        self?.codexActivity = activity
        self?.evaluateMode()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        awakeMode = loadAwakeMode()
        buildMenu()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if awakeMode == .auto {
            codexMonitor.start()
        }
        monitorTimer = Timer.scheduledTimer(timeInterval: 2,
                                            target: self,
                                            selector: #selector(monitorTick),
                                            userInfo: nil,
                                            repeats: true)
        RunLoop.main.add(monitorTimer!, forMode: .common)
        evaluateMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        codexMonitor.stop()
        if awakeMode == .auto {
            setSleepDisabled(false)
        }
        systemSleepAssertion.setActive(false)
    }

    func buildMenu() {
        menu = NSMenu()
        menu.delegate = self

        modeRow = ModeRow(target: self, action: #selector(modeChanged))
        let modeItem = NSMenuItem()
        modeItem.view = modeRow
        menu.addItem(modeItem)

        loginRow = LoginRow(target: self, action: #selector(loginFlipped))
        let loginItem = NSMenuItem()
        loginItem.view = loginRow
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let hint = NSMenuItem(title: S.hint, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: S.quit,
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    // A three-state choice can't be represented by a single instant toggle, so
    // either mouse button opens the mode menu.
    @objc func statusItemClicked() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func modeChanged() {
        guard let selected = AwakeMode(segment: modeRow.modeControl.selectedSegment) else {
            return
        }
        let previousMode = awakeMode
        awakeMode = selected
        UserDefaults.standard.set(selected.rawValue, forKey: modeDefaultsKey)
        idleGraceDeadline = nil
        if selected == .auto && previousMode != .auto {
            codexActivity = .connecting
            codexMonitor.start()
        } else if selected != .auto && previousMode == .auto {
            codexMonitor.stop()
            codexActivity = .connecting
        }
        evaluateMode()
        menu.cancelTracking()
    }

    @objc func monitorTick() {
        evaluateMode()
    }

    @objc func loginFlipped() {
        guard #available(macOS 13.0, *) else {
            refreshLoginItem()
            return
        }

        let service = SMAppService.mainApp
        let enable = loginRow.modeControl.selectedSegment == 0

        do {
            if enable {
                if service.status == .notRegistered || service.status == .notFound {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            NSLog("AwakeToggle login item error: \(error)")
        }

        refreshLoginItem()
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        menu.cancelTracking()
    }

    func menuWillOpen(_ menu: NSMenu) {
        evaluateMode()
    }

    func loadAwakeMode() -> AwakeMode {
        if let raw = UserDefaults.standard.string(forKey: modeDefaultsKey),
           let saved = AwakeMode(rawValue: raw) {
            return saved
        }
        return isOn() ? .on : .off
    }

    func evaluateMode() {
        let activeCount = codexActivity.activeCount
        let desiredOn: Bool

        switch awakeMode {
        case .on:
            idleGraceDeadline = nil
            desiredOn = true
        case .off:
            idleGraceDeadline = nil
            desiredOn = false
        case .auto:
            if codexActivity.availability == .available && activeCount > 0 {
                idleGraceDeadline = nil
                desiredOn = true
            } else if codexActivity.availability != .available {
                if idleGraceDeadline == nil && (lastActiveCount > 0 || isOn()) {
                    idleGraceDeadline = Date().addingTimeInterval(idleGraceSeconds)
                }
                if let deadline = idleGraceDeadline, deadline > Date() {
                    desiredOn = isOn()
                } else {
                    idleGraceDeadline = nil
                    desiredOn = false
                }
            } else {
                if lastActiveCount > 0 {
                    idleGraceDeadline = Date().addingTimeInterval(idleGraceSeconds)
                }
                if let deadline = idleGraceDeadline, deadline > Date() {
                    desiredOn = true
                } else {
                    idleGraceDeadline = nil
                    desiredOn = false
                }
            }
        }

        lastActiveCount = activeCount
        setKeepAwake(desiredOn)
        clamshellDisplaySleepController.reconcile(
            keepAwakeEnabled: desiredOn
        )
        refreshUI()
    }

    func setKeepAwake(_ enabled: Bool) {
        if enabled {
            // Acquire the process-scoped assertion first, then apply the global
            // lid-close setting. This closes the activation window in which
            // ordinary system sleep could otherwise occur.
            systemSleepAssertion.setActive(true)
            setSleepDisabled(true)
        } else {
            setSleepDisabled(false)
            systemSleepAssertion.setActive(false)
        }
    }

    // Reading the current state needs no privileges.
    func isOn() -> Bool {
        for line in shell("/usr/bin/pmset", ["-g"]).split(separator: "\n")
            where line.contains("SleepDisabled") {
            return line.contains("1")
        }
        return false
    }

    func setSleepDisabled(_ disabled: Bool) {
        guard isOn() != disabled else { return }
        _ = shell("/usr/bin/sudo",
                  ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"])
    }

    func refreshUI() {
        let actualOn = isOn()
        if let button = statusItem.button {
            button.image = actualOn ? iconClosed : iconOpen
            button.toolTip = S.tooltip(mode: awakeMode,
                                       actualOn: actualOn,
                                       activity: codexActivity)
        }
        modeRow.update(mode: awakeMode, activity: codexActivity)
        refreshLoginItem()
    }

    func refreshLoginItem() {
        guard #available(macOS 13.0, *) else {
            loginRow.modeControl.isEnabled = false
            loginRow.update(on: false, subtitle: S.launchUnavailable)
            return
        }

        loginRow.modeControl.isEnabled = true
        switch SMAppService.mainApp.status {
        case .enabled:
            loginRow.update(on: true)
        case .requiresApproval:
            loginRow.update(on: true, subtitle: S.launchApproval)
        case .notRegistered, .notFound:
            loginRow.update(on: false)
        @unknown default:
            loginRow.update(on: false)
        }
    }

    func shell(_ launchPath: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@main
struct AwakeToggleApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        app.run()
    }
}
