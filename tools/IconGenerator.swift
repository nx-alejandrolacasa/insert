import AppKit
import CoreText

// Insert app icon: a soft, modern mark for a projects / notes / tasks app.
// A pastel gradient tile (lilac → warm apricot) with two stacked, glassy white
// "note" cards; the front card carries a few text lines and a checkmark badge —
// notes + tasks, at a glance. Minimalistic and "Liquid Glass" adjacent.
//
// Regeneration recipe: CLAUDE.md → "App icon".

// MARK: - Palette (pastel purple + warm orange)

private let bgTop = NSColor(srgbRed: 0.82, green: 0.78, blue: 0.99, alpha: 1)      // pastel lilac
private let bgBottom = NSColor(srgbRed: 0.99, green: 0.86, blue: 0.72, alpha: 1)   // warm apricot
private let cardFront = NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)  // clean white
private let cardBack = NSColor(srgbRed: 0.97, green: 0.96, blue: 1.00, alpha: 1)   // faint lilac-white
private let lineTint = NSColor(srgbRed: 0.80, green: 0.81, blue: 0.87, alpha: 1)   // soft gray text lines
// The check badge picks up the warm end of the tile so both hues sing.
private let badgeTop = NSColor(srgbRed: 0.66, green: 0.52, blue: 0.98, alpha: 1)   // purple
private let badgeBottom = NSColor(srgbRed: 0.99, green: 0.66, blue: 0.42, alpha: 1) // orange

// MARK: - Helpers

private func roundedPath(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

private func linearGradient(_ cg: CGContext, _ rect: CGRect, _ top: NSColor, _ bottom: NSColor,
                            start: CGPoint? = nil, end: CGPoint? = nil) {
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(grad,
                          start: start ?? CGPoint(x: rect.midX, y: rect.maxY),
                          end: end ?? CGPoint(x: rect.midX, y: rect.minY), options: [])
}

/// Draws one rounded card, rotated about its own center, with a soft drop
/// shadow, a gentle top sheen and a hairline edge.
private func drawCard(_ cg: CGContext, center: CGPoint, size: CGSize, corner: CGFloat,
                      rotation: CGFloat, fill: NSColor, showContent: Bool) {
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: rotation)

    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let path = roundedPath(rect, corner)

    // Drop shadow + fill.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor(white: 0, alpha: 0.22).cgColor)
    cg.addPath(path); cg.setFillColor(fill.cgColor); cg.fillPath()
    cg.restoreGState()

    // Top sheen for a glassy lift.
    cg.saveGState(); cg.addPath(path); cg.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor(white: 1, alpha: 0.9).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.maxY),
                          end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    cg.restoreGState()

    // Hairline edge.
    cg.addPath(path)
    cg.setStrokeColor(NSColor(white: 0, alpha: 0.05).cgColor)
    cg.setLineWidth(2); cg.strokePath()

    if showContent {
        // Text lines near the top of the card.
        let lx = rect.minX + size.width * 0.16
        let lw = size.width * 0.62
        let lh = size.height * 0.05
        let gap = size.height * 0.115
        var ly = rect.maxY - size.height * 0.26
        let widths: [CGFloat] = [1.0, 0.86, 0.55]
        for factor in widths {
            let lr = CGRect(x: lx, y: ly, width: lw * factor, height: lh)
            cg.addPath(roundedPath(lr, lh / 2)); cg.setFillColor(lineTint.cgColor); cg.fillPath()
            ly -= gap
        }

        // Checkmark badge, bottom-right, slightly overhanging.
        let badgeR = size.width * 0.25
        let badgeRect = CGRect(x: rect.maxX - badgeR * 1.35, y: rect.minY - badgeR * 0.3,
                               width: badgeR * 2, height: badgeR * 2)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor(white: 0, alpha: 0.25).cgColor)
        cg.addEllipse(in: badgeRect); cg.setFillColor(badgeBottom.cgColor); cg.fillPath()
        cg.restoreGState()
        cg.saveGState(); cg.addEllipse(in: badgeRect); cg.clip()
        linearGradient(cg, badgeRect, badgeTop, badgeBottom)
        cg.restoreGState()

        // The check glyph (y-up: the vee's vertex is the lowest point).
        let bx = badgeRect.midX, by = badgeRect.midY, s = badgeR
        let check = CGMutablePath()
        check.move(to: CGPoint(x: bx - s * 0.46, y: by + s * 0.02))
        check.addLine(to: CGPoint(x: bx - s * 0.10, y: by - s * 0.34))
        check.addLine(to: CGPoint(x: bx + s * 0.50, y: by + s * 0.40))
        cg.addPath(check)
        cg.setStrokeColor(NSColor.white.cgColor)
        cg.setLineWidth(s * 0.30); cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.strokePath()
    }

    cg.restoreGState()
}

// MARK: - Compose

private func drawIcon(_ cg: CGContext) {
    let canvas: CGFloat = 1024
    let inset: CGFloat = 96
    let content = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let tilePath = roundedPath(content, content.width * 0.235)

    // Soft drop shadow beneath the tile.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: NSColor(white: 0, alpha: 0.18).cgColor)
    cg.addPath(tilePath); cg.setFillColor(bgBottom.cgColor); cg.fillPath()
    cg.restoreGState()

    // Pastel diagonal gradient tile (lilac top-left → apricot bottom-right).
    cg.saveGState(); cg.addPath(tilePath); cg.clip()
    linearGradient(cg, content, bgTop, bgBottom,
                   start: CGPoint(x: content.minX, y: content.maxY),
                   end: CGPoint(x: content.maxX, y: content.minY))
    cg.restoreGState()

    // Two stacked cards: a faint one behind (up-right, tilted) and the white
    // content card in front (down-left, slight opposite tilt).
    let cardW = content.width * 0.52
    let cardH = content.height * 0.60
    let corner = content.width * 0.11
    let cx = content.midX, cy = content.midY

    drawCard(cg,
             center: CGPoint(x: cx + content.width * 0.065, y: cy + content.height * 0.075),
             size: CGSize(width: cardW * 0.9, height: cardH * 0.9),
             corner: corner * 0.9, rotation: 8 * .pi / 180,
             fill: cardBack, showContent: false)

    drawCard(cg,
             center: CGPoint(x: cx - content.width * 0.04, y: cy - content.height * 0.035),
             size: CGSize(width: cardW, height: cardH),
             corner: corner, rotation: -4 * .pi / 180,
             fill: cardFront, showContent: true)

    // Whisper-thin inner rim on the tile for a crisp edge.
    cg.saveGState()
    cg.addPath(tilePath)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.30).cgColor)
    cg.setLineWidth(2); cg.strokePath()
    cg.restoreGState()
}

// MARK: - Render + output

private func renderMaster() -> NSBitmapImageRep {
    let px = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawIcon(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func png(_ master: NSBitmapImageRep, size: Int) -> Data {
    if size == 1024 { return master.representation(using: .png, properties: [:])! }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    master.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let master = renderMaster()

let fm = FileManager.default
let outputDir = "AppIcon.iconset"
try? fm.removeItem(atPath: outputDir)
try! fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in targets {
    try! png(master, size: size).write(to: URL(fileURLWithPath: "\(outputDir)/\(name)"))
}
try! png(master, size: 1024).write(to: URL(fileURLWithPath: "AppIcon-preview.png"))
print("Wrote \(outputDir) and AppIcon-preview.png")
