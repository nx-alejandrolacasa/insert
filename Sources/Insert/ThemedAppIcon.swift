import AppKit
import SwiftUI

/// The Dock icon, redrawn in the theme's colours — one icon per theme.
///
/// The design is the shipped icon's (two stacked cards, a check badge) with the
/// theme's own values in the two places colour lives: the tile is a subtle
/// vertical gradient of the theme's **band** — the band lightened a step at the
/// top, darkened a step at the bottom — and the badge wears the **accent**, with
/// the tick in the theme's **second** colour, the one its count chip spends
/// (asked for over `primaryLabel`: the chip hue carries more contrast on the
/// badge and reads as the theme where a near-black tick read as chrome). The
/// chip's two halves are a deep fill in Light and a bright numeral in Dark, so
/// the tick takes whichever of the two sits further from the badge it's drawn
/// on — a pale badge gets the deep half, a deep badge the bright one.
/// Cards stay white with grey lines whatever the theme, exactly as on screen.
///
/// Set through `NSApp.applicationIconImage`, which is the only way to change a
/// Mac app's icon while it runs — rewriting the bundle's `.icns` would break its
/// signature. The honest limit: **Finder, Launchpad and the login-items list
/// keep the shipped icon**; the swap covers the Dock, the app switcher and
/// Mission Control, and only while Insert is running. Re-applied on a theme
/// change (`SettingsStore.theme`) and on every effective-appearance flip
/// (`AppDelegate`'s KVO), because the band and accent resolve per appearance and
/// a Dock icon rendered once would keep the wrong half.
///
/// The geometry mirrors `tools/IconGenerator.swift`'s `Design` fractions for the
/// flat `.icns` — the two aren't shared code (the tool is a script, not part of
/// this target), so a proportion changed there should be changed here too or the
/// running icon drifts from the shipped one.
@MainActor
enum ThemedAppIcon {
    static func apply(_ theme: AppTheme) {
        // `NSApp` is nil under `swift test`, where `SettingsStore.theme` is
        // still written — there is no Dock tile there to draw for.
        guard let app = NSApp, let image = render(theme, under: app.effectiveAppearance)
        else { return }
        app.applicationIconImage = image
    }

    // MARK: Rendering

    private static func render(_ theme: AppTheme, under appearance: NSAppearance) -> NSImage? {
        let canvas = 1024
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        // Pin the appearance while the dynamic colours resolve, so the icon
        // drawn is the half the window is actually wearing.
        appearance.performAsCurrentDrawingAppearance {
            draw(theme, in: ctx.cgContext, canvas: CGFloat(canvas))
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.addRepresentation(rep)
        return image
    }

    private static func draw(_ theme: AppTheme, in cg: CGContext, canvas: CGFloat) {
        let band = NSColor(theme.band.fill)
        let accent = NSColor(theme.primary)
        let tick = tickColor(for: theme, on: accent)

        // "Subtle gradient": the band's own tone, lifted and settled a step.
        let bgTop = band.blended(withFraction: 0.08, of: .white) ?? band
        let bgBottom = band.blended(withFraction: 0.12, of: .black) ?? band
        let badgeTop = accent.blended(withFraction: 0.18, of: .white) ?? accent
        let badgeBottom = accent.blended(withFraction: 0.18, of: .black) ?? accent

        let inset = canvas * 96 / 1024
        let content = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
        let tile = CGPath(roundedRect: content, cornerWidth: content.width * 0.235,
                          cornerHeight: content.width * 0.235, transform: nil)

        // Tile: soft shadow, then the theme gradient.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 50,
                     color: NSColor(white: 0, alpha: 0.18).cgColor)
        cg.addPath(tile)
        cg.setFillColor(bgBottom.cgColor)
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(tile)
        cg.clip()
        gradient(cg, from: bgTop, to: bgBottom,
                 start: CGPoint(x: content.midX, y: content.maxY),
                 end: CGPoint(x: content.midX, y: content.minY))
        cg.restoreGState()

        // The two cards, back then front — the same fractions as the tool.
        let cardW = content.width * 0.52
        let cardH = content.height * 0.60
        let corner = content.width * 0.11
        let deg = CGFloat.pi / 180
        card(cg,
             center: CGPoint(x: content.midX + content.width * 0.065,
                             y: content.midY + content.height * 0.075),
             size: CGSize(width: cardW * 0.9, height: cardH * 0.9),
             corner: corner * 0.9, rotation: 8 * deg,
             badgeTop: badgeTop, badgeBottom: badgeBottom, tick: tick, showContent: false)
        card(cg,
             center: CGPoint(x: content.midX - content.width * 0.04,
                             y: content.midY - content.height * 0.035),
             size: CGSize(width: cardW, height: cardH),
             corner: corner, rotation: -4 * deg,
             badgeTop: badgeTop, badgeBottom: badgeBottom, tick: tick, showContent: true)

        cg.addPath(tile)
        cg.setStrokeColor(NSColor(white: 1, alpha: 0.30).cgColor)
        cg.setLineWidth(2)
        cg.strokePath()
    }

    private static func card(_ cg: CGContext, center: CGPoint, size: CGSize, corner: CGFloat,
                             rotation: CGFloat, badgeTop: NSColor, badgeBottom: NSColor,
                             tick: NSColor, showContent: Bool) {
        let front = NSColor.white
        let back = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        let line = NSColor(srgbRed: 0.80, green: 0.81, blue: 0.87, alpha: 1)

        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: rotation)

        let rect = CGRect(x: -size.width / 2, y: -size.height / 2,
                          width: size.width, height: size.height)
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner,
                          transform: nil)

        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                     color: NSColor(white: 0, alpha: 0.22).cgColor)
        cg.addPath(path)
        cg.setFillColor((showContent ? front : back).cgColor)
        cg.fillPath()
        cg.restoreGState()

        cg.addPath(path)
        cg.setStrokeColor(NSColor(white: 0, alpha: 0.05).cgColor)
        cg.setLineWidth(2)
        cg.strokePath()

        if showContent {
            let lx = rect.minX + size.width * 0.16
            let lw = size.width * 0.62
            let lh = size.height * 0.05
            var ly = rect.maxY - size.height * 0.26
            for factor in [1.0, 0.86, 0.55] as [CGFloat] {
                let lr = CGRect(x: lx, y: ly, width: lw * factor, height: lh)
                cg.addPath(CGPath(roundedRect: lr, cornerWidth: lh / 2, cornerHeight: lh / 2,
                                  transform: nil))
                cg.setFillColor(line.cgColor)
                cg.fillPath()
                ly -= size.height * 0.115
            }

            let r = size.width * 0.25
            let badge = CGRect(x: rect.maxX - r * 1.35, y: rect.minY - r * 0.3,
                               width: r * 2, height: r * 2)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 12,
                         color: NSColor(white: 0, alpha: 0.25).cgColor)
            cg.addEllipse(in: badge)
            cg.setFillColor(badgeBottom.cgColor)
            cg.fillPath()
            cg.restoreGState()
            cg.saveGState()
            cg.addEllipse(in: badge)
            cg.clip()
            gradient(cg, from: badgeTop, to: badgeBottom,
                     start: CGPoint(x: badge.midX, y: badge.maxY),
                     end: CGPoint(x: badge.midX, y: badge.minY))
            cg.restoreGState()

            let bx = badge.midX, by = badge.midY
            let check = CGMutablePath()
            check.move(to: CGPoint(x: bx - r * 0.46, y: by + r * 0.02))
            check.addLine(to: CGPoint(x: bx - r * 0.10, y: by - r * 0.34))
            check.addLine(to: CGPoint(x: bx + r * 0.50, y: by + r * 0.40))
            cg.addPath(check)
            cg.setStrokeColor(tick.cgColor)
            cg.setLineWidth(r * 0.30)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
        }

        cg.restoreGState()
    }

    /// The chip colour half that contrasts more with the badge. Resolved under
    /// explicit appearances, because the two halves live in one dynamic colour
    /// and the deep one is the *light* half whatever the window is wearing.
    private static func tickColor(for theme: AppTheme, on badge: NSColor) -> NSColor {
        let deep = resolved(theme.band.countFill, under: .aqua)
        let bright = resolved(theme.band.countText, under: .darkAqua)
        let base = luminance(badge)
        return abs(luminance(deep) - base) >= abs(luminance(bright) - base) ? deep : bright
    }

    private static func resolved(_ color: Color, under name: NSAppearance.Name) -> NSColor {
        var out = NSColor(color)
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            out = NSColor(cgColor: NSColor(color).cgColor) ?? out
        }
        return out
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ u: CGFloat) -> CGFloat {
            u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent)
            + 0.0722 * linear(c.blueComponent)
    }

    private static func gradient(_ cg: CGContext, from top: NSColor, to bottom: NSColor,
                                 start: CGPoint, end: CGPoint) {
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [top.cgColor, bottom.cgColor] as CFArray,
                                    locations: [0, 1]) else { return }
        cg.drawLinearGradient(grad, start: start, end: end, options: [])
    }
}
