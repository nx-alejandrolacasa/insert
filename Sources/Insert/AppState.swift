import Observation
import SwiftUI

/// Transient, window-level UI state shared across the three panels and the
/// command palette. Not persisted (except where it seeds from `SettingsStore`).
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    /// Selected project, or `nil` for "All" (show everything).
    var selectedProjectID: UUID?

    /// The note currently open for editing, or `nil` when every note is shown
    /// in read-only (rendered) mode. Only one note edits at a time.
    var selectedNoteID: UUID?

    /// The task currently open for editing — same contract as `selectedNoteID`:
    /// `nil` means every task row is in its compact read-only shape.
    var selectedTaskID: UUID?

    /// Whether the projects sidebar is visible (toggled from the header glyphs,
    /// the palette or the ⌘§ shortcut).
    var sidebarVisible: Bool = true

    /// The one note type on show, or `nil` for all of them. Single-select like
    /// the tasks column's All / Pending / Done — the pill rows are the same
    /// control, so they behave the same way.
    var noteTypeFilter: String?

    /// Live tasks filter — the state axis (All / Pending / Done).
    var taskFilter: TaskFilter = .pending

    /// The date axis, ANDed with `taskFilter`. `nil` is the dropdown's
    /// "All time" default — the axis switched off.
    var taskDateFilter: TaskDateFilter?

    /// Measured height of the window's title-bar + toolbar region (see
    /// `WindowConfigurator`). The sidebar header matches it so its title lands
    /// level with the columns' headings, instead of a hard-coded guess that
    /// drifts with the toolbar style.
    var titlebarHeight: CGFloat = Metrics.titlebarHeight

    /// Vertical centre of the traffic lights, measured down from the top of the
    /// window's content view — the line AppKit puts toolbar controls on. The
    /// sidebar's own buttons align to *this* rather than to the middle of
    /// `titlebarHeight`: with a unified toolbar the band is taller than the
    /// lights' row, so centring in the band sits them too low.
    var trafficLightCenterY: CGFloat = 20

    private init() {}
}
