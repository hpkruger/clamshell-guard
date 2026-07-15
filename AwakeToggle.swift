import Cocoa

// AwakeToggle — a menu-bar switch for `pmset -a disablesleep`.
// Left-click the icon toggles instantly; right-click opens the menu.
// Toggling asks for the admin password via the native macOS auth dialog,
// so no passwordless-sudo entry or privileged helper is required.

// MARK: - Icons

// A laptop seen edge-on: hinge at the back-right, front lip to the left.
// closed == true  -> lid resting on the base: always-on is ACTIVE, the lid can
//                    shut without the machine sleeping.
// closed == false -> lid cracked open: normal power behaviour.
func laptopIcon(closed: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    NSColor.black.setStroke()
    let lw: CGFloat = 1.1

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

    img.unlockFocus()
    img.isTemplate = true
    return img
}

// MARK: - Switch row shown inside the menu

final class SwitchRow: NSView {
    let toggle = NSSwitch()
    let title = NSTextField(labelWithString: "保持在线常驻")
    let subtitle = NSTextField(labelWithString: "合盖也不休眠")

    init(target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 48))
        title.font = .menuFont(ofSize: 13)
        subtitle.font = .menuFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        toggle.target = target
        toggle.action = action

        title.frame = NSRect(x: 14, y: 26, width: 170, height: 16)
        subtitle.frame = NSRect(x: 14, y: 9, width: 170, height: 14)
        toggle.frame = NSRect(x: 194, y: 14, width: 42, height: 22)

        addSubview(title)
        addSubview(subtitle)
        addSubview(toggle)
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

        switchRow = SwitchRow(target: self, action: #selector(switchFlipped))
        let rowItem = NSMenuItem()
        rowItem.view = switchRow
        menu.addItem(rowItem)

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "提示：左键点图标可直接切换", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    func menuWillOpen(_ menu: NSMenu) {
        switchRow.toggle.state = isOn() ? .on : .off
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
            button.toolTip = on
                ? "常驻在线：开 — 合盖也不休眠（点击关闭）"
                : "常驻在线：关 — 正常休眠（点击开启）"
        }
        switchRow.toggle.state = on ? .on : .off
    }

    func toggleAwake() {
        let target = isOn() ? "0" : "1"
        let src = "do shell script \"/usr/bin/pmset -a disablesleep \(target)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err = err { NSLog("AwakeToggle error: \(err)") }
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
