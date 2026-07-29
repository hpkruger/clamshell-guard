import Cocoa

// This file is compiled with drawLaptop() extracted from ClamshellGuard.swift.
// The application icon deliberately uses the open-lid menu glyph.

guard CommandLine.arguments.count == 2 else {
    fputs("usage: export-app-icon <output.iconset>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1],
                          isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory,
                                        withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(pixels: Int) throws -> Data {
    let dimension = CGFloat(pixels)
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "ClamshellGuardIcon", code: 1)
    }
    representation.size = NSSize(width: dimension, height: dimension)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw NSError(domain: "ClamshellGuardIcon", code: 2)
    }

    context.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    let inset = dimension * 0.085
    let backgroundRect = NSRect(x: inset,
                                y: inset,
                                width: dimension - 2 * inset,
                                height: dimension - 2 * inset)
    let background = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: dimension * 0.19,
        yRadius: dimension * 0.19
    )

    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.31, blue: 0.92, alpha: 1),
        ending: NSColor(srgbRed: 0.55, green: 0.08, blue: 0.95, alpha: 1)
    )
    gradient?.draw(in: background, angle: -45)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    background.lineWidth = max(1, dimension * 0.012)
    background.stroke()

    // The open glyph occupies x=1.8...16.7 and y=4.6...15.0 on its 18x18
    // design grid. Scale and translate those visual bounds to the icon centre.
    let scale = dimension * 0.045
    let visualCentre = NSPoint(x: 9.25, y: 9.78)
    context.saveGState()
    context.translateBy(x: dimension / 2 - visualCentre.x * scale,
                        y: dimension / 2 - visualCentre.y * scale)
    context.scaleBy(x: scale, y: scale)

    NSColor.white.setStroke()
    let minimumPixelStroke: CGFloat = 1.5
    drawLaptop(closed: false,
               lineWidth: max(1.1, minimumPixelStroke / scale))
    context.restoreGState()

    guard let png = representation.representation(using: .png,
                                                  properties: [:]) else {
        throw NSError(domain: "ClamshellGuardIcon", code: 3)
    }
    return png
}

for variant in variants {
    let destination = outputDirectory.appendingPathComponent(variant.name)
    try renderIcon(pixels: variant.pixels).write(to: destination)
}

print("Generated \(variants.count) icon images in \(outputDirectory.path)")
