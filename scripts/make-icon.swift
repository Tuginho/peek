import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-icon.swift <svg-path> <iconset-dir>\n".data(using: .utf8)!)
    exit(1)
}

let svgPath = args[1]
let iconsetDir = args[2]

guard let image = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
    FileHandle.standardError.write("error: could not load SVG at \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

do {
    try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write("error: could not create \(iconsetDir): \(error)\n".data(using: .utf8)!)
    exit(1)
}

struct Entry {
    let name: String
    let size: Int
}

let entries: [Entry] = [
    Entry(name: "icon_16x16", size: 16),
    Entry(name: "icon_16x16@2x", size: 32),
    Entry(name: "icon_32x32", size: 32),
    Entry(name: "icon_32x32@2x", size: 64),
    Entry(name: "icon_128x128", size: 128),
    Entry(name: "icon_128x128@2x", size: 256),
    Entry(name: "icon_256x256", size: 256),
    Entry(name: "icon_256x256@2x", size: 512),
    Entry(name: "icon_512x512", size: 512),
    Entry(name: "icon_512x512@2x", size: 1024),
]

func render(size: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("error: could not create bitmap rep for size \(size)\n".data(using: .utf8)!)
        exit(1)
    }
    // Pixel size == point size: no Retina (@2x) scaling sneaks into the drawing.
    rep.size = NSSize(width: size, height: size)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write("error: could not create graphics context for size \(size)\n".data(using: .utf8)!)
        exit(1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for entry in entries {
    let rep = render(size: entry.size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("error: could not encode PNG for \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let outPath = (iconsetDir as NSString).appendingPathComponent("\(entry.name).png")
    do {
        try data.write(to: URL(fileURLWithPath: outPath))
    } catch {
        FileHandle.standardError.write("error: could not write \(outPath): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Sanity check on the largest render: corners outside the rounded rect must
// be transparent, the center of the artwork must be opaque.
let verifyRep = render(size: 1024)
func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
    rep.colorAt(x: x, y: y)?.alphaComponent ?? -1
}

let cornerAlpha = alpha(verifyRep, x: 0, y: 0)
let centerAlpha = alpha(verifyRep, x: 512, y: 512)

if cornerAlpha > 0.01 {
    FileHandle.standardError.write("error: corner pixel (0,0) is not transparent (alpha=\(cornerAlpha))\n".data(using: .utf8)!)
    exit(1)
}
if centerAlpha < 0.99 {
    FileHandle.standardError.write("error: center pixel (512,512) is not opaque (alpha=\(centerAlpha))\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(entries.count) icon images to \(iconsetDir)")
