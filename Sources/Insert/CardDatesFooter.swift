import SwiftUI

/// The timestamp line at the foot of a note or task card:
///
///     ✦ 12 Jun 2026, 09:14  ·  ✎ 27 Jul 2026, 15:02
///
/// Which stamps appear is a `CardDates` setting, one per card kind (Settings →
/// Notes / Tasks). Icons rather than prose — "Created on X · Updated on Y" says
/// the same thing in four more words per card — with the wording kept for the
/// spoken label, where the glyphs don't reach. ✦ (sparkles) is "newly made",
/// ✎ the edit.
struct CardDatesFooter: View {
    enum Kind { case note, task }

    let kind: Kind
    let created: Date
    let updated: Date

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if showCreated || showUpdated {
            HStack(spacing: 4) {
                if showCreated {
                    segment(icon: "sparkles", date: created)
                }
                if showCreated && showUpdated {
                    Text("·")
                }
                if showUpdated {
                    segment(icon: "pencil", date: updated)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
        }
    }

    private var display: CardDates {
        switch kind {
        case .note: settings.noteCardDates
        case .task: settings.taskCardDates
        }
    }

    /// "Edited" is judged at the minute the footer displays, so a card whose
    /// timestamps differ only by the save that created it still counts as fresh.
    private var edited: Bool { abs(updated.timeIntervalSince(created)) >= 60 }

    private var showCreated: Bool { display.showsCreated(edited: edited) }
    private var showUpdated: Bool { display.showsUpdated(edited: edited) }

    private func segment(icon: String, date: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(date, format: Self.format)
        }
    }

    private var spokenLabel: String {
        var parts: [String] = []
        if showCreated { parts.append("Created \(created.formatted(Self.format))") }
        if showUpdated { parts.append("Edited \(updated.formatted(Self.format))") }
        return parts.joined(separator: ", ")
    }

    /// The style the footer has always used, through the app's English locale.
    private static let format: Date.FormatStyle = .dateTime
        .month().day().year().hour().minute().locale(Formatting.locale)
}
