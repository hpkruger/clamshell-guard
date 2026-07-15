import Cocoa

// Renders the blog/README thumbnail: the two real menu-bar states side by side.
//
// This file is concatenated onto AwakeToggle.swift (minus its app bootstrap) by
// tools/export-thumbnail.sh, so drawLaptop() below is literally the shipping
// glyph code — the thumbnail cannot drift from what users see in the menu bar.
//
// Usage: export-thumbnail.sh <out.png> [font-dir]

let W: CGFloat = 1200
let H: CGFloat = 630
let scale: CGFloat = 2   // render retina, tag the rep as 1200x630 points

let purple = NSColor(srgbRed: 0x8a / 255.0, green: 0x05 / 255.0, blue: 0xff / 255.0, alpha: 1)
let gray900 = NSColor(srgbRed: 0x11 / 255.0, green: 0x18 / 255.0, blue: 0x27 / 255.0, alpha: 1)
let gray500 = NSColor(srgbRed: 0x6b / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0, alpha: 1)
let gray200 = NSColor(srgbRed: 0xe5 / 255.0, green: 0xe7 / 255.0, blue: 0xeb / 255.0, alpha: 1)
let gray25 = NSColor(srgbRed: 0xfa / 255.0, green: 0xfa / 255.0, blue: 0xfa / 255.0, alpha: 1)

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "thumbnail.png"

// Register the site's real typeface if its directory was passed in, so the image
// matches the page it sits on rather than falling back to the system font.
if args.count > 2 {
    let dir = URL(fileURLWithPath: args[2])
    for name in ["PlusJakartaSans-Light.ttf", "PlusJakartaSans-Medium.ttf"] {
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

func font(_ names: [String], _ size: CGFloat, fallback: NSFont.Weight) -> NSFont {
    for n in names { if let f = NSFont(name: n, size: size) { return f } }
    FileHandle.standardError.write("warn: falling back to system font at \(size)pt\n".data(using: .utf8)!)
    return NSFont.systemFont(ofSize: size, weight: fallback)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

gray25.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// The glyph's own bounds inside the 18x18 design grid. The closed slab sits
// 1.8 units higher than the open laptop's base, so drawing both box-centred
// leaves them visually floating at different heights; align on the base
// instead, as if both machines sat on the same desk.
let baseY: (Bool) -> CGFloat = { closed in closed ? 6.4 : 4.6 }

func glyph(closed: Bool, cx: CGFloat, baselineY: CGFloat, size: CGFloat) {
    ctx.saveGState()
    let k = size / 18.0
    // Shift so the glyph's own base lands on baselineY.
    ctx.translateBy(x: cx - size / 2, y: baselineY - baseY(closed) * k)
    ctx.scaleBy(x: k, y: k)
    purple.setStroke()
    drawLaptop(closed: closed)   // native 1.1 line width keeps the menu-bar proportions
    ctx.restoreGState()
}

func text(_ s: String, _ f: NSFont, _ color: NSColor, centeredAt cx: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
    let size = (s as NSString).size(withAttributes: attrs)
    (s as NSString).draw(at: NSPoint(x: cx - size.width / 2, y: y), withAttributes: attrs)
}

let display = font(["PlusJakartaSans-Light"], 52, fallback: .light)
let bodyFont = font(["PlusJakartaSans-Medium"], 26, fallback: .regular)
let monoFont = NSFont.monospacedSystemFont(ofSize: 19, weight: .medium)

let leftX = W * 0.28
let rightX = W * 0.72
let glyphSize: CGFloat = 280
let baseline = H * 0.31   // where both laptops "rest"

glyph(closed: false, cx: leftX, baselineY: baseline, size: glyphSize)
glyph(closed: true, cx: rightX, baselineY: baseline, size: glyphSize)

gray200.setFill()
NSRect(x: W / 2 - 0.5, y: H * 0.13, width: 1, height: H * 0.50).fill()

text("OFF", monoFont, gray500, centeredAt: leftX, y: H * 0.225)
text("ON", monoFont, purple, centeredAt: rightX, y: H * 0.225)
text("Normal sleep", bodyFont, gray500, centeredAt: leftX, y: H * 0.15)
text("Lid closed, still awake", bodyFont, gray900, centeredAt: rightX, y: H * 0.15)

text("AwakeToggle", display, gray900, centeredAt: W / 2, y: H * 0.775)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode png\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(W * scale))x\(Int(H * scale)))")
