import AppKit

/// App appearance preference: Auto / Light / Dark.
///
/// **The setting is called "Mode" on screen** (Settings → Appearance), not
/// "Appearance": the pane is named that, and a row of the same name under it
/// printed the word three times on one screen. The type keeps its name, since
/// `NSAppearance` is what it wraps — see `AppearanceSettingsTab` for why the label
/// moved rather than `AppTheme`'s.
enum Appearance: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: Self { self }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The `NSAppearance` to apply — `nil` means "follow the system" (Auto).
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
