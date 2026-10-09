// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // Background squircle on the standard macOS icon grid.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(red: 0.29, green: 0.56, blue: 0.95, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.30, blue: 0.72, alpha: 1))!
        .draw(in: tile, angle: -90)

    NSColor.white.setStroke()
    NSColor.white.setFill()

    // Laptop screen and base.
    let screen = NSBezierPath(roundedRect: NSRect(x: 272, y: 410, width: 480, height: 310), xRadius: 30, yRadius: 30)
    screen.lineWidth = 36
    screen.stroke()
    NSBezierPath(roundedRect: NSRect(x: 212, y: 338, width: 600, height: 44), xRadius: 22, yRadius: 22).fill()

    // Crescent moon on the screen.
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
    clip.append(NSBezierPath(ovalIn: NSRect(x: 535 - 78, y: 600 - 78, width: 156, height: 156)))
    clip.windingRule = .evenOdd
    clip.addClip()
    NSBezierPath(ovalIn: NSRect(x: 505 - 92, y: 565 - 92, width: 184, height: 184)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return true
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(output.path)")
