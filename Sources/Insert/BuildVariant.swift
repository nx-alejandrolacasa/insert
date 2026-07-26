import Foundation

/// Which of the two builds this is.
///
/// `build.sh` produces a dev variant by default and the release one only for
/// `release` / `install`, suffixing the dev bundle id with `.dev` (mirroring
/// prtscn). macOS keys UserDefaults and the Documents-folder grant to the bundle
/// id, so the two run side by side with separate settings and separate
/// permission grants — nothing here has to arrange that.
///
/// What *does* need arranging is the notes folder. A dev build gets its own
/// defaults, so it never inherits the real build's saved `rootFolderPath` and
/// falls back to the default — which for dev is deliberately a different folder,
/// so exercising a delete or the completed-task sweep can't reach real notes.
enum BuildVariant {
    /// True when running the dev bundle. Read from the bundle id rather than a
    /// compile-time flag so one binary serves both variants and `build.sh` stays
    /// the only place that decides.
    static var isDev: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    /// Folder name under `~/Documents` used when nothing has been chosen yet.
    static var defaultFolderName: String {
        isDev ? "Insert Dev" : "Insert"
    }

    /// Suffix for anything user-visible that should say which build it is.
    /// Empty for the release build so its UI is unchanged.
    static var titleSuffix: String {
        isDev ? " Dev" : ""
    }
}
