import Cocoa
import ServiceManagement

// AwakeToggle — a menu-bar switch for `pmset -a disablesleep`.
// Left-click the icon toggles instantly; right-click opens the menu.
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
    static let subtitle = t("No sleep when lid closes",
                            "合盖也不休眠",
                            "Pas de veille écran fermé")
    static let hint = t("Tip: left-click the icon to toggle",
                        "提示：左键点图标可直接切换",
                        "Astuce : clic gauche sur l'icône pour basculer")
    static let quit = t("Quit", "退出", "Quitter")
    static let on = t("ON", "开启", "ACTIF")
    static let off = t("OFF", "关闭", "INACTIF")
    static let approval = t("APPROVAL", "需批准", "APPROBATION")
    static let unavailable = t("UNAVAILABLE", "不可用", "INDISPONIBLE")
    static let launchTitle = t("Launch on Login", "登录时启动", "Ouvrir à la connexion")
    static let launchSubtitle = t("Start AwakeToggle automatically",
                                  "登录后自动启动 AwakeToggle",
                                  "Démarrer AwakeToggle automatiquement")

    static func tooltip(on: Bool) -> String {
        on
            ? t("Keep Awake: ON — lid close won't sleep (click to turn off)",
                "常驻在线：开 — 合盖也不休眠（点击关闭）",
                "Rester éveillé : ACTIVÉ — pas de veille écran fermé (cliquer pour désactiver)")
            : t("Keep Awake: OFF — normal sleep (click to turn on)",
                "常驻在线：关 — 正常休眠（点击开启）",
                "Rester éveillé : DÉSACTIVÉ — veille normale (cliquer pour activer)")
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
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let iconClosed = laptopIcon(closed: true)
    let iconOpen = laptopIcon(closed: false)
    var menu: NSMenu!
    var switchRow: SwitchRow!
    var loginRow: SwitchRow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
    }

    func buildMenu() {
        menu = NSMenu()
        menu.delegate = self

        switchRow = SwitchRow(title: S.title,
                              subtitle: S.subtitle,
                              target: self,
                              action: #selector(switchFlipped))
        let rowItem = NSMenuItem()
        rowItem.view = switchRow
        menu.addItem(rowItem)

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
        menu.addItem(NSMenuItem(title: S.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // Left-click toggles; right-click (or control-click) opens the menu.
    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil      // release it so left-click keeps toggling
        } else {
            toggleAwake()
        }
    }

    @objc func switchFlipped() {
        toggleAwake()
        menu.cancelTracking()
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
        switchRow.setOn(isOn())
        refreshLoginItem()
    }

    // Reading the current state needs no privileges.
    func isOn() -> Bool {
        for line in shell("/usr/bin/pmset", ["-g"]).split(separator: "\n") where line.contains("SleepDisabled") {
            return line.contains("1")
        }
        return false
    }

    func refresh() {
        let on = isOn()
        if let button = statusItem.button {
            button.image = on ? iconClosed : iconOpen
            button.toolTip = S.tooltip(on: on)
        }
        switchRow.setOn(on)
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

    func toggleAwake() {
        let target = isOn() ? "0" : "1"
        _ = shell("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", target])
        refresh()
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
