import AppKit

struct IconSpec { let size: Int; let scale: Int }

let specs: [IconSpec] = [
    .init(size: 16, scale: 1), .init(size: 16, scale: 2),
    .init(size: 32, scale: 1), .init(size: 32, scale: 2),
    .init(size: 128, scale: 1), .init(size: 128, scale: 2),
    .init(size: 256, scale: 1), .init(size: 256, scale: 2),
    .init(size: 512, scale: 1), .init(size: 512, scale: 2),
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let assetDir = URL(fileURLWithPath: "mac-notice/Assets.xcassets/AppIcon.appiconset", relativeTo: cwd)
try? fm.createDirectory(at: assetDir, withIntermediateDirectories: true)

func drawBaseIcon(_ dimension: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: dimension, height: dimension))
    img.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: dimension, height: dimension)
    let radius = CGFloat(dimension) * 0.18 // slightly rounded, more like a note card
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Background gradient (teal -> orange, complementary vibe)
    // Gradient: #27C5F5 (39,197,245) -> #F55727 (245,87,39)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 39.0/255.0, green: 197.0/255.0, blue: 245.0/255.0, alpha: 1.0),
        NSColor(calibratedRed: 245.0/255.0, green: 87.0/255.0,  blue: 39.0/255.0,  alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -18)

    // Subtle top highlight "glass" sheen
    let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: dimension.cg * 0.10, dy: dimension.cg * 0.58), xRadius: radius, yRadius: radius)
    NSColor(white: 1.0, alpha: 0.16).setFill()
    highlight.fill()

    // Bottom soft shadow
    let shadow = NSBezierPath(roundedRect: rect.insetBy(dx: dimension.cg * 0.06, dy: dimension.cg * 0.06), xRadius: radius, yRadius: radius)
    NSColor(white: 0.0, alpha: 0.07).setFill()
    shadow.fill()

    // Folded corner cue (top-right) to evoke sticky-note
    let fold = dimension.cg * 0.16
    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: rect.maxX - fold, y: rect.maxY))
    foldPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
    foldPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY - fold))
    foldPath.close()
    NSColor(white: 1.0, alpha: 0.18).setFill()
    foldPath.fill()
    NSColor(white: 1.0, alpha: 0.12).setStroke()
    foldPath.lineWidth = max(1.0, dimension.cg * 0.01)
    foldPath.stroke()

    // Symbol (SF Symbol note)
    if let sym = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil) {
        let scale = CGFloat(dimension) * 0.46
        let symRect = NSRect(
            x: (CGFloat(dimension) - scale) / 2,
            y: (CGFloat(dimension) - scale) / 2,
            width: scale,
            height: scale
        )

        // Drop shadow for symbol
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.setShadow(offset: .init(width: 0, height: dimension.cg * 0.012), blur: dimension.cg * 0.04, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        NSColor.white.set()
        sym.draw(in: symRect)
        ctx?.restoreGState()
    }

    img.unlockFocus()
    return img
}

extension Int { var cg: CGFloat { CGFloat(self) } }

// Write Contents.json if missing
let contentsURL = assetDir.appendingPathComponent("Contents.json")
if !fm.fileExists(atPath: contentsURL.path) {
    let images: [[String: Any]] = specs.map { spec in
        let sizeStr = "\(spec.size)x\(spec.size)"
        let fileName = spec.scale == 1 ? "icon_\(spec.size).png" : "icon_\(spec.size)@2x.png"
        return [
            "idiom": "mac",
            "size": sizeStr,
            "scale": "\(spec.scale)x",
            "filename": fileName
        ]
    }
    let json: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: contentsURL)
}

// Generate images
let base = drawBaseIcon(1024)

for spec in specs {
    let px = spec.size * spec.scale
    let outName = spec.scale == 1 ? "icon_\(spec.size).png" : "icon_\(spec.size)@2x.png"
    let outURL = assetDir.appendingPathComponent(outName)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = ctx
        base.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.current = nil
    }
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: outURL)
        fputs("wrote \(outName)\n", stderr)
    }
}

print("AppIcon generated at: \(assetDir.path)")
