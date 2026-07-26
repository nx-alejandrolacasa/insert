import AppKit
import CoreText

// Insert app icon: a soft, modern mark for a projects / notes / tasks app.
// A pastel gradient tile (lilac → warm apricot) with two stacked, glassy white
// "note" cards; the front card carries a few text lines and a checkmark badge —
// notes + tasks, at a glance. Minimalistic and "Liquid Glass" adjacent.
//
// Regenerate with `./build.sh icon`; design notes in CLAUDE.md → Design intent →
// Icon.
//
// This emits the icon **twice**, from one set of proportions, because macOS 26
// and every macOS before it want opposite things:
//
//   AppIcon.icon/     Layered, for Icon Composer / actool. Full-bleed, *unmasked*
//                     square layers with no baked-in shadows, sheen or bevels —
//                     the system draws the corner radius, the specular highlights
//                     and the refraction, and generates the dark / clear / tinted
//                     variants. HIG: "Providing layers with pre-defined masking
//                     negatively impacts specular highlight effects and makes
//                     edges look jagged", and "let the system handle blurring and
//                     other visual effects".
//   AppIcon.iconset/  The classic flat raster set, still the fallback when the
//                     layered icon can't be compiled. Nothing supplies effects to
//                     a plain .icns, so this one *keeps* its own rounded tile,
//                     inset margin, drop shadows and sheen. That difference is
//                     deliberate; don't "fix" it by aligning the two.

// MARK: - Palette (pastel purple + warm orange)

private let bgTop = NSColor(srgbRed: 0.82, green: 0.78, blue: 0.99, alpha: 1)      // pastel lilac
private let bgBottom = NSColor(srgbRed: 0.99, green: 0.86, blue: 0.72, alpha: 1)   // warm apricot
private let cardFront = NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)  // clean white
private let cardBack = NSColor(srgbRed: 0.97, green: 0.96, blue: 1.00, alpha: 1)   // faint lilac-white
private let lineTint = NSColor(srgbRed: 0.80, green: 0.81, blue: 0.87, alpha: 1)   // soft gray text lines
// The check badge picks up the warm end of the tile so both hues sing.
private let badgeTop = NSColor(srgbRed: 0.66, green: 0.52, blue: 0.98, alpha: 1)   // purple
private let badgeBottom = NSColor(srgbRed: 0.99, green: 0.66, blue: 0.42, alpha: 1) // orange

private extension NSColor {
    /// `#RRGGBB`, for SVG.
    var hex: String {
        let c = usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

// MARK: - Geometry

/// The design as fractions of whatever square it's drawn into, so the layered
/// (full-bleed) and legacy (inset tile) renders stay the same drawing.
///
/// The layered icon fills the whole 1024 canvas; the legacy one draws into a tile
/// inset by `legacyInset`. Feeding the same fractions to a different base rect is
/// the only difference between them.
private enum Design {
    static let canvas: CGFloat = 1024
    /// Margin the flat .icns leaves around its tile. The layered icon has none —
    /// the system's mask provides the shape and the breathing room.
    static let legacyInset: CGFloat = 96

    /// Corner radius of the legacy tile, as a fraction of its width.
    static let tileCorner: CGFloat = 0.235

    static let cardWidth: CGFloat = 0.52
    static let cardHeight: CGFloat = 0.60
    static let cardCorner: CGFloat = 0.11
    /// The back card is a touch smaller than the front one.
    static let backCardScale: CGFloat = 0.9

    /// Card centre offsets from the middle, as fractions. Positive y is *up*.
    static let backOffset = CGPoint(x: 0.065, y: 0.075)
    static let frontOffset = CGPoint(x: -0.04, y: -0.035)

    static let backRotation: CGFloat = 8      // degrees, counter-clockwise
    static let frontRotation: CGFloat = -4

    // Text lines on the front card, as fractions of the card.
    static let lineInset: CGFloat = 0.16
    static let lineWidth: CGFloat = 0.62
    static let lineHeight: CGFloat = 0.05
    static let lineGap: CGFloat = 0.115
    static let lineTop: CGFloat = 0.26
    static let lineWidthFactors: [CGFloat] = [1.0, 0.86, 0.55]

    /// Badge radius as a fraction of the front card's width.
    static let badgeRadius: CGFloat = 0.25
}

// MARK: - SVG emission (the layered .icon)

/// Minimal SVG writer. Only the handful of primitives this icon needs.
///
/// Coordinates are SVG's own — origin top-left, **y down** — computed directly
/// rather than flipped from the CoreGraphics render below, because a global flip
/// would also invert the gradients and make every number here read backwards.
private struct SVG {
    private var body = ""
    private var defs = ""
    let size: CGFloat

    init(size: CGFloat) { self.size = size }

    mutating func linearGradient(id: String, from: NSColor, to: NSColor,
                                 x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) {
        // `userSpaceOnUse` is not optional here: SVG's default is
        // `objectBoundingBox`, where the coordinates are 0–1 fractions of the
        // shape's box. Passing absolute canvas coordinates without this makes
        // every stop past the first fall off the end of the ramp, and the
        // gradient silently renders as a flat first colour.
        defs += """
              <linearGradient id="\(id)" gradientUnits="userSpaceOnUse" \
        x1="\(f(x1))" y1="\(f(y1))" x2="\(f(x2))" y2="\(f(y2))">
                <stop offset="0" stop-color="\(from.hex)"/>
                <stop offset="1" stop-color="\(to.hex)"/>
              </linearGradient>\n
        """
    }

    /// Opens a group carrying a card's placement: moved to its centre, then
    /// rotated about it. SVG rotates clockwise for positive angles where
    /// CoreGraphics rotates counter-clockwise, so the sign is flipped here.
    mutating func beginCard(center: CGPoint, rotationCCW: CGFloat) {
        body += "  <g transform=\"translate(\(f(center.x)) \(f(center.y))) rotate(\(f(-rotationCCW)))\">\n"
    }

    mutating func endCard() { body += "  </g>\n" }

    /// A rounded rect centred on the current origin.
    mutating func centeredRoundedRect(size s: CGSize, corner: CGFloat, fill: String) {
        body += """
              <rect x="\(f(-s.width / 2))" y="\(f(-s.height / 2))" width="\(f(s.width))" \
        height="\(f(s.height))" rx="\(f(corner))" fill="\(fill)"/>\n
        """
    }

    mutating func roundedRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                             corner: CGFloat, fill: String) {
        body += """
              <rect x="\(f(x))" y="\(f(y))" width="\(f(w))" height="\(f(h))" \
        rx="\(f(corner))" fill="\(fill)"/>\n
        """
    }

    mutating func circle(cx: CGFloat, cy: CGFloat, r: CGFloat, fill: String) {
        body += "    <circle cx=\"\(f(cx))\" cy=\"\(f(cy))\" r=\"\(f(r))\" fill=\"\(fill)\"/>\n"
    }

    /// An open polyline, stroked with round caps and joins (the checkmark).
    mutating func polyline(_ points: [CGPoint], stroke: NSColor, width: CGFloat) {
        let d = points.enumerated()
            .map { "\($0.offset == 0 ? "M" : "L")\(f($0.element.x)) \(f($0.element.y))" }
            .joined(separator: " ")
        body += """
              <path d="\(d)" fill="none" stroke="\(stroke.hex)" stroke-width="\(f(width))" \
        stroke-linecap="round" stroke-linejoin="round"/>\n
        """
    }

    var document: String {
        let defsBlock = defs.isEmpty ? "" : "  <defs>\n\(defs)  </defs>\n"
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(f(size))" height="\(f(size))" \
        viewBox="0 0 \(f(size)) \(f(size))">
        \(defsBlock)\(body)</svg>

        """
    }

    /// Trims trailing zeros so the output reads as design values, not float noise.
    private func f(_ v: CGFloat) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(Double(r))
    }
}

/// The four unmasked, full-bleed layers of the layered icon.
private func layerSVGs() -> [(name: String, svg: String)] {
    let c = Design.canvas
    let mid = CGPoint(x: c / 2, y: c / 2)

    // --- Background: full bleed, fully opaque, no corner radius. The system
    // masks it; drawing our own rounded tile here would fight the mask and
    // wreck the specular highlights along the edge.
    var background = SVG(size: c)
    background.linearGradient(id: "tile", from: bgTop, to: bgBottom,
                              x1: 0, y1: 0, x2: c, y2: c)   // lilac top-left → apricot bottom-right
    background.roundedRect(x: 0, y: 0, w: c, h: c, corner: 0, fill: "url(#tile)")

    // --- Card geometry, now measured against the whole canvas.
    let cardSize = CGSize(width: c * Design.cardWidth, height: c * Design.cardHeight)
    let backSize = CGSize(width: cardSize.width * Design.backCardScale,
                          height: cardSize.height * Design.backCardScale)
    let corner = c * Design.cardCorner
    // Design offsets are y-up; SVG is y-down, hence the negated y.
    let backCenter = CGPoint(x: mid.x + c * Design.backOffset.x,
                             y: mid.y - c * Design.backOffset.y)
    let frontCenter = CGPoint(x: mid.x + c * Design.frontOffset.x,
                              y: mid.y - c * Design.frontOffset.y)

    // --- Back card: its own layer, so the system lights it separately and the
    // stack reads as two sheets rather than one flat shape.
    var back = SVG(size: c)
    back.beginCard(center: backCenter, rotationCCW: Design.backRotation)
    back.centeredRoundedRect(size: backSize, corner: corner * Design.backCardScale,
                             fill: cardBack.hex)
    back.endCard()

    // --- Front card, with its text lines. The lines ride along with the card,
    // so they share its group and its rotation.
    var front = SVG(size: c)
    front.beginCard(center: frontCenter, rotationCCW: Design.frontRotation)
    front.centeredRoundedRect(size: cardSize, corner: corner, fill: cardFront.hex)
    let lh = cardSize.height * Design.lineHeight
    let lw = cardSize.width * Design.lineWidth
    let lx = -cardSize.width / 2 + cardSize.width * Design.lineInset
    for (i, factor) in Design.lineWidthFactors.enumerated() {
        // y-up placed each line by its *bottom* edge; y-down wants its top.
        let top = -(cardSize.height * (Design.lineTop + Design.lineHeight))
            + CGFloat(i) * cardSize.height * Design.lineGap
        front.roundedRect(x: lx, y: top, w: lw * factor, h: lh, corner: lh / 2, fill: lineTint.hex)
    }
    front.endCard()

    // --- Badge: also its own layer. It's the one element that wants to catch
    // the light independently, and it overhangs the card's corner.
    let r = cardSize.width * Design.badgeRadius
    let badgeCenter = CGPoint(x: cardSize.width / 2 - r * 1.35 + r,
                              y: cardSize.height / 2 + r * 0.3 - r)
    var badge = SVG(size: c)
    badge.linearGradient(id: "badge", from: badgeTop, to: badgeBottom,
                         x1: badgeCenter.x, y1: badgeCenter.y - r,
                         x2: badgeCenter.x, y2: badgeCenter.y + r)
    badge.beginCard(center: frontCenter, rotationCCW: Design.frontRotation)
    badge.circle(cx: badgeCenter.x, cy: badgeCenter.y, r: r, fill: "url(#badge)")
    badge.polyline([
        CGPoint(x: badgeCenter.x - r * 0.46, y: badgeCenter.y - r * 0.02),
        CGPoint(x: badgeCenter.x - r * 0.10, y: badgeCenter.y + r * 0.34),
        CGPoint(x: badgeCenter.x + r * 0.50, y: badgeCenter.y - r * 0.40),
    ], stroke: .white, width: r * 0.30)
    badge.endCard()

    return [
        ("background", background.document),
        ("back-card", back.document),
        ("front-card", front.document),
        ("badge", badge.document),
    ]
}

/// The `.icon` package's manifest.
///
/// `.icon` is a document *package* (`com.apple.iconcomposer.icon` conforms to
/// `com.apple.package`), so it's a plain folder we can write. The schema below
/// is the subset this icon needs — one group per layer, so each gets its own
/// system lighting rather than sharing one group's treatment.
///
/// Caveat worth knowing: this manifest format isn't publicly documented. If a
/// future Icon Composer disagrees with it, open `AppIcon.icon` in Icon Composer
/// (Xcode → Open Developer Tool) and re-add the same SVGs from `Assets/` — the
/// layers are the real artifact here and they're what the design lives in.
private let iconManifest = """
{
  "groups" : [
    {
      "layers" : [
        { "image-name" : "background.svg", "name" : "Background" }
      ]
    },
    {
      "layers" : [
        { "image-name" : "back-card.svg", "name" : "Back Card" }
      ]
    },
    {
      "layers" : [
        { "image-name" : "front-card.svg", "name" : "Front Card" }
      ]
    },
    {
      "layers" : [
        { "image-name" : "badge.svg", "name" : "Badge" }
      ]
    }
  ],
  "supported-platforms" : {
    "circles" : [ "watchOS" ],
    "squares" : [ "iOS", "macOS" ]
  }
}

"""

// MARK: - Legacy raster (the flat .icns fallback)

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
///
/// The effects here are *only* for the flat .icns, which nothing else decorates.
/// The layered icon deliberately ships none of them.
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
        let lx = rect.minX + size.width * Design.lineInset
        let lw = size.width * Design.lineWidth
        let lh = size.height * Design.lineHeight
        let gap = size.height * Design.lineGap
        var ly = rect.maxY - size.height * Design.lineTop
        for factor in Design.lineWidthFactors {
            let lr = CGRect(x: lx, y: ly, width: lw * factor, height: lh)
            cg.addPath(roundedPath(lr, lh / 2)); cg.setFillColor(lineTint.cgColor); cg.fillPath()
            ly -= gap
        }

        // Checkmark badge, bottom-right, slightly overhanging.
        let badgeR = size.width * Design.badgeRadius
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

private func drawLegacyIcon(_ cg: CGContext) {
    let canvas = Design.canvas
    let inset = Design.legacyInset
    let content = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let tilePath = roundedPath(content, content.width * Design.tileCorner)

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
    let cardW = content.width * Design.cardWidth
    let cardH = content.height * Design.cardHeight
    let corner = content.width * Design.cardCorner
    let cx = content.midX, cy = content.midY
    let deg = CGFloat.pi / 180

    drawCard(cg,
             center: CGPoint(x: cx + content.width * Design.backOffset.x,
                             y: cy + content.height * Design.backOffset.y),
             size: CGSize(width: cardW * Design.backCardScale, height: cardH * Design.backCardScale),
             corner: corner * Design.backCardScale, rotation: Design.backRotation * deg,
             fill: cardBack, showContent: false)

    drawCard(cg,
             center: CGPoint(x: cx + content.width * Design.frontOffset.x,
                             y: cy + content.height * Design.frontOffset.y),
             size: CGSize(width: cardW, height: cardH),
             corner: corner, rotation: Design.frontRotation * deg,
             fill: cardFront, showContent: true)

    // Whisper-thin inner rim on the tile for a crisp edge.
    cg.saveGState()
    cg.addPath(tilePath)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.30).cgColor)
    cg.setLineWidth(2); cg.strokePath()
    cg.restoreGState()
}

private func renderMaster() -> NSBitmapImageRep {
    let px = Int(Design.canvas)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawLegacyIcon(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func png(_ master: NSBitmapImageRep, size: Int) -> Data {
    if size == Int(Design.canvas) { return master.representation(using: .png, properties: [:])! }
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

// MARK: - Output

let fm = FileManager.default

// 1. The layered icon: AppIcon.icon/{icon.json, Assets/*.svg}
let iconPackage = "AppIcon.icon"
try? fm.removeItem(atPath: iconPackage)
try! fm.createDirectory(atPath: "\(iconPackage)/Assets", withIntermediateDirectories: true)
try! iconManifest.write(to: URL(fileURLWithPath: "\(iconPackage)/icon.json"),
                        atomically: true, encoding: .utf8)
for (name, svg) in layerSVGs() {
    try! svg.write(to: URL(fileURLWithPath: "\(iconPackage)/Assets/\(name).svg"),
                   atomically: true, encoding: .utf8)
}

// 2. The flat fallback set, plus a preview.
let master = renderMaster()
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

print("Wrote \(iconPackage) (4 unmasked layers), \(outputDir) and AppIcon-preview.png")
