import Cocoa
import Darwin
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
    static let approval = t("APPROVAL", "需批准", "APPROBATION")
    static let unavailable = t("UNAVAILABLE", "不可用", "INDISPONIBLE")
    static let launchTitle = t("Launch on Login", "登录时启动", "Ouvrir à la connexion")
    static let launchSubtitle = t("Start AwakeToggle automatically",
                                  "登录后自动启动 AwakeToggle",
                                  "Démarrer AwakeToggle automatiquement")

    static let alwaysAwake = t("Always preventing sleep",
                               "始终阻止休眠",
                               "Veille toujours désactivée")
    static let normalSleep = t("Normal macOS sleep",
                               "正常 macOS 休眠",
                               "Veille macOS normale")
    static let autoIdle = t("AUTO · No active Codex tasks",
                            "自动 · 没有活动的 Codex 任务",
                            "AUTO · Aucune tâche Codex active")

    static func autoActive(_ count: Int) -> String {
        t("AUTO · \(count) active Codex task\(count == 1 ? "" : "s")",
          "自动 · \(count) 个活动的 Codex 任务",
          "AUTO · \(count) tâche\(count == 1 ? "" : "s") Codex active\(count == 1 ? "" : "s")")
    }

    static func tooltip(mode: AwakeMode, actualOn: Bool, activeCount: Int) -> String {
        switch mode {
        case .on:
            return t("Keep Awake: ON — always preventing sleep",
                     "常驻在线：开启 — 始终阻止休眠",
                     "Rester éveillé : ACTIF — veille toujours désactivée")
        case .auto:
            return actualOn
                ? autoActive(activeCount)
                : autoIdle
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

struct TurnMarker: Codable {
    let sessionID: String
    let turnID: String
    let appServerPID: Int32
    let startedAt: Date
}

func activeTurnDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory,
                             in: .userDomainMask)[0]
        .appendingPathComponent("AwakeToggle/active-turns", isDirectory: true)
}

func executablePath(of pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
}

func isCodexDesktopAppServer(_ pid: pid_t) -> Bool {
    guard let path = executablePath(of: pid),
          path.hasSuffix(".app/Contents/Resources/codex") else { return false }
    let appURL = URL(fileURLWithPath: path)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return Bundle(url: appURL)?.bundleIdentifier == "com.openai.codex"
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
    init() {
        super.init(frame: .zero)
        segmentCount = 3
        trackingMode = .selectOne
        setLabel(S.on, forSegment: 0)
        setLabel(S.auto, forSegment: 1)
        setLabel(S.off, forSegment: 2)
        selectedSegment = AwakeMode.off.segment
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let background = NSBezierPath(roundedRect: outer, xRadius: 6, yRadius: 6)
        NSColor.quaternaryLabelColor.setFill()
        background.fill()

        let segmentWidth = outer.width / 3
        let selected = NSRect(x: outer.minX + CGFloat(selectedSegment) * segmentWidth,
                              y: outer.minY,
                              width: segmentWidth,
                              height: outer.height)
        let selectedPath = NSBezierPath(roundedRect: selected.insetBy(dx: 1, dy: 1),
                                        xRadius: 5,
                                        yRadius: 5)
        let selectedColor: NSColor
        switch AwakeMode(segment: selectedSegment) {
        case .on: selectedColor = .systemGreen
        case .auto: selectedColor = .systemBlue
        case .off, .none: selectedColor = .systemGray
        }
        selectedColor.setFill()
        selectedPath.fill()

        let font = NSFont.boldSystemFont(ofSize: 10)
        for index in 0..<3 {
            let label = label(forSegment: index) ?? ""
            let color = index == selectedSegment ? NSColor.white : NSColor.labelColor
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
    let modeControl = ModeControl()
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

    func update(mode: AwakeMode, activeCount: Int) {
        modeControl.selectedSegment = mode.segment
        modeControl.needsDisplay = true
        switch mode {
        case .on:
            subtitle.stringValue = S.alwaysAwake
            subtitle.textColor = .systemGreen
        case .auto where activeCount > 0:
            subtitle.stringValue = S.autoActive(activeCount)
            subtitle.textColor = .systemGreen
        case .auto:
            subtitle.stringValue = S.autoIdle
            subtitle.textColor = .secondaryLabelColor
        case .off:
            subtitle.stringValue = S.normalSleep
            subtitle.textColor = .secondaryLabelColor
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

// NSSwitch uses an inactive grey track when a menu-bar-only app is not the
// foreground application. Draw the track explicitly so the ON state remains
// unmistakable even while another app is active.
final class AwakeSwitch: NSSwitch {
    var onColor = NSColor.systemGreen {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let track = NSBezierPath(roundedRect: trackRect,
                                 xRadius: trackRect.height / 2,
                                 yRadius: trackRect.height / 2)
        (state == .on ? onColor : NSColor.tertiaryLabelColor).setFill()
        track.fill()

        let inset: CGFloat = 2
        let knobSize = trackRect.height - inset * 2
        let knobX = state == .on
            ? trackRect.maxX - inset - knobSize
            : trackRect.minX + inset
        let knobRect = NSRect(x: knobX,
                              y: trackRect.minY + inset,
                              width: knobSize,
                              height: knobSize)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class SwitchRow: NSView {
    let toggle = AwakeSwitch()
    let title: NSTextField
    let subtitle: NSTextField
    let stateLabel = NSTextField(labelWithString: S.off)

    init(title titleText: String,
         subtitle subtitleText: String,
         extraStateLabels: [String] = [],
         target: AnyObject,
         action: Selector) {
        title = NSTextField(labelWithString: titleText)
        subtitle = NSTextField(labelWithString: subtitleText)
        super.init(frame: .zero)
        title.font = .menuFont(ofSize: 13)
        subtitle.font = .menuFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let stateFont = NSFont.boldSystemFont(ofSize: 11)
        stateLabel.font = stateFont
        stateLabel.alignment = .right
        toggle.target = target
        toggle.action = action

        // Size the row to its own text so every language fits without clipping,
        // instead of hard-coding a width that only suits one of them.
        title.sizeToFit()
        subtitle.sizeToFit()
        let textWidth = max(title.frame.width, subtitle.frame.width)
        let stateWidth = ([S.on, S.off] + extraStateLabels)
            .map { ($0 as NSString).size(withAttributes: [.font: stateFont]).width }
            .max() ?? 0
        let padding: CGFloat = 14
        let gap: CGFloat = 24
        let stateGap: CGFloat = 9
        let switchWidth: CGFloat = 42

        frame = NSRect(x: 0, y: 0,
                       width: padding + textWidth + gap + stateWidth + stateGap
                            + switchWidth + padding,
                       height: 48)
        title.frame = NSRect(x: padding, y: 25,
                             width: textWidth, height: title.frame.height)
        subtitle.frame = NSRect(x: padding, y: 9,
                                width: textWidth, height: subtitle.frame.height)
        stateLabel.frame = NSRect(x: padding + textWidth + gap, y: 17,
                                  width: stateWidth, height: 14)
        toggle.frame = NSRect(x: stateLabel.frame.maxX + stateGap, y: 13,
                              width: switchWidth, height: 22)

        addSubview(title)
        addSubview(subtitle)
        addSubview(stateLabel)
        addSubview(toggle)
    }

    func setOn(_ on: Bool) {
        setState(on: on,
                 label: on ? S.on : S.off,
                 color: on ? .systemGreen : .secondaryLabelColor)
    }

    func setState(on: Bool, label: String, color: NSColor) {
        toggle.onColor = color
        toggle.state = on ? .on : .off
        toggle.needsDisplay = true
        stateLabel.stringValue = label
        stateLabel.textColor = color
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
    var loginRow: SwitchRow!
    var awakeMode = AwakeMode.off
    var monitorTimer: Timer?
    var lastActiveCount = 0
    var idleGraceDeadline: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        awakeMode = loadAwakeMode()
        buildMenu()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        if awakeMode == .auto {
            setSleepDisabled(false)
        }
    }

    func buildMenu() {
        menu = NSMenu()
        menu.delegate = self

        modeRow = ModeRow(target: self, action: #selector(modeChanged))
        let modeItem = NSMenuItem()
        modeItem.view = modeRow
        menu.addItem(modeItem)

        loginRow = SwitchRow(title: S.launchTitle,
                             subtitle: S.launchSubtitle,
                             extraStateLabels: [S.approval, S.unavailable],
                             target: self,
                             action: #selector(loginFlipped))
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
        awakeMode = selected
        UserDefaults.standard.set(selected.rawValue, forKey: modeDefaultsKey)
        idleGraceDeadline = nil
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
        let enable = loginRow.toggle.state == .on

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

    func activeCodexTurnCount() -> Int {
        let directory = activeTurnDirectory()
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var count = 0
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let marker = try? decoder.decode(TurnMarker.self, from: data),
                  isCodexDesktopAppServer(marker.appServerPID) else {
                try? fileManager.removeItem(at: file)
                continue
            }
            count += 1
        }
        return count
    }

    func evaluateMode() {
        let activeCount = activeCodexTurnCount()
        let desiredOn: Bool

        switch awakeMode {
        case .on:
            idleGraceDeadline = nil
            desiredOn = true
        case .off:
            idleGraceDeadline = nil
            desiredOn = false
        case .auto:
            if activeCount > 0 {
                idleGraceDeadline = nil
                desiredOn = true
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
        setSleepDisabled(desiredOn)
        refreshUI(activeCount: activeCount)
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

    func refreshUI(activeCount: Int) {
        let actualOn = isOn()
        if let button = statusItem.button {
            button.image = actualOn ? iconClosed : iconOpen
            button.toolTip = S.tooltip(mode: awakeMode,
                                       actualOn: actualOn,
                                       activeCount: activeCount)
        }
        modeRow.update(mode: awakeMode, activeCount: activeCount)
        refreshLoginItem()
    }

    func refreshLoginItem() {
        guard #available(macOS 13.0, *) else {
            loginRow.toggle.isEnabled = false
            loginRow.setState(on: false, label: S.unavailable, color: .secondaryLabelColor)
            return
        }

        loginRow.toggle.isEnabled = true
        switch SMAppService.mainApp.status {
        case .enabled:
            loginRow.setOn(true)
        case .requiresApproval:
            loginRow.setState(on: true, label: S.approval, color: .systemOrange)
        case .notRegistered, .notFound:
            loginRow.setOn(false)
        @unknown default:
            loginRow.setOn(false)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
