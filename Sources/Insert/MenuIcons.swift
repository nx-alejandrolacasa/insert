import AppKit
import SwiftUI

/// SF Symbols for **menu items**, resolved once as `NSImage`s.
///
/// This exists for one measured reason. A SwiftUI `Menu` on macOS is an
/// `NSPopUpButton`, and AppKit rebuilds every `NSMenuItem` on **every graph
/// update** — the menu does not have to be open. An item written as
/// `Label(_, systemImage:)` hands SwiftUI a symbol *name*, and rebuilding it
/// resolves that name's accessibility description through
/// `AXSwiftUIDescriptionForSymbolName` → `_CFBundleCopyLocalizedStringForLocalization…`
/// → `_copyStringTable`: an **uncached** localized-string-table load, complete
/// with binary-plist filtering and ICU locale parsing, per item per card per
/// update. In a `sample` of a 3.4s freeze that was 624 of 3369 samples, with
/// another 108 resolving the images themselves.
///
/// The expensive lookup is keyed on the symbol **name**, so the fix is to not
/// hand a name over: an `NSImage` resolved here once and passed as
/// `Image(nsImage:)` has no name for SwiftUI to describe. The images are
/// memoised for the process because a symbol is a constant — same input, same
/// picture, forever.
///
/// **`accessibilityDescription` is deliberately `nil`.** These images always sit
/// in a `Label` beside their own `Text`, and that text is the item's accessible
/// name; a description on the image as well would have VoiceOver say the thing
/// twice. It is also the whole point — a described symbol is what the expensive
/// path exists to produce.
///
/// **Unverified as of writing.** That skipping the name skips the lookup follows
/// from the trace, but it has not been measured in a running app; `LayoutProbe`
/// is what would settle it. If a menu-heavy view still stalls with the probe on,
/// this is the first thing to suspect, and the fallback is a bare `Text` item
/// (which is what the two ⋯ menus wore in between).
enum MenuIcons {
    private static let images = MemoCache<String, NSImage?>(limit: 64)

    /// The symbol as a template image, or `nil` if this macOS doesn't have it —
    /// in which case the caller draws the label's text alone, which is the
    /// honest degradation for a decoration.
    static func image(_ symbol: String) -> NSImage? {
        images.value(for: symbol) {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            return image
        }
    }

    /// A menu item's label: its name, with the symbol beside it when the system
    /// has one. Every `Menu` item in the app that wants an icon goes through
    /// here, so there is one place the name-free rule is kept.
    @ViewBuilder
    static func label(_ title: String, _ symbol: String) -> some View {
        if let image = image(symbol) {
            Label { Text(title) } icon: { Image(nsImage: image) }
        } else {
            Text(title)
        }
    }
}
