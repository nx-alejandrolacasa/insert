import Foundation
import SwiftUI

/// A month grid that fills whatever width it is given.
///
/// `DatePicker(.graphical)` on macOS is an `NSDatePicker`, and that view has a
/// fixed 139×148 intrinsic size at *every* control size — it can't be asked to
/// fill a popover, and scaling it up just rasterizes the text. So the grid is
/// drawn here instead: it stays crisp at any size and can wear the app's tints.
///
/// Names are English and the layout is regional: the grid formats through
/// `Formatting.calendar`, so weekday and month names come out in the app's
/// language while the week still starts on `Calendar.firstWeekday` (Monday here).
struct MonthCalendar: View {
    @Binding var selection: Date
    /// The tint the grid wears. A `Tint` rather than a single `Color` because the
    /// two things that need colouring want opposite ends of it: the selected day
    /// is a *fill* carrying white type (`deep`), while today's marker and the
    /// "Today" button are *foreground* on the popover surface (`ink`). One colour
    /// couldn't be legible as both.
    var tint: Tint = .blue

    /// The month on screen, which the user can page away from the selection.
    @State private var visibleMonth: Date

    init(selection: Binding<Date>, tint: Tint = .blue) {
        _selection = selection
        self.tint = tint
        _visibleMonth = State(
            initialValue: MonthGrid.startOfMonth(for: selection.wrappedValue, calendar: Formatting.calendar)
        )
    }

    private static let rowHeight: CGFloat = 28

    var body: some View {
        let calendar = Formatting.calendar

        VStack(spacing: 6) {
            header(calendar)
            weekdayRow(calendar)
            grid(calendar)
        }
        // Picking a date elsewhere (a preset pill) should bring its month up.
        .onChange(of: selection) { _, newValue in
            visibleMonth = MonthGrid.startOfMonth(for: newValue, calendar: Formatting.calendar)
        }
    }

    // MARK: - Header

    private func header(_ calendar: Calendar) -> some View {
        HStack(spacing: 2) {
            Text(MonthGrid.title(for: visibleMonth, calendar: calendar))
                .font(.headline)

            Spacer(minLength: 8)

            stepButton(systemImage: "chevron.left", help: "Previous month") { step(-1, calendar) }
            Button {
                visibleMonth = MonthGrid.startOfMonth(for: Date(), calendar: calendar)
            } label: {
                Text("Today")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tint.ink)
            .padding(.horizontal, 4)
            .help("Jump to this month")
            stepButton(systemImage: "chevron.right", help: "Next month") { step(1, calendar) }
        }
    }

    private func stepButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                // 20pt was under a comfortable click target for a control people
                // page through repeatedly; the chevron itself is unchanged.
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private func step(_ months: Int, _ calendar: Calendar) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        visibleMonth = MonthGrid.startOfMonth(for: moved, calendar: calendar)
    }

    // MARK: - Grid

    private func weekdayRow(_ calendar: Calendar) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(MonthGrid.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(_ calendar: Calendar) -> some View {
        let days = MonthGrid.days(for: visibleMonth, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days, id: \.self) { day in
                dayCell(day, calendar: calendar, today: today)
            }
        }
    }

    private func dayCell(_ day: Date, calendar: Calendar, today: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)

        return Button {
            selection = calendar.startOfDay(for: day)
        } label: {
            Text(day, format: .dateTime.day().locale(Formatting.locale))
                // `.callout` is 12pt on macOS — same size, but it now follows the
                // system text size rather than pinning itself.
                .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, inMonth: inMonth))
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
                // Cells are wider than they are tall, so a rounded rectangle
                // fits the shape better than the usual circle.
                .background {
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    if isSelected {
                        shape.fill(tint.deep)
                    } else if isToday {
                        shape.strokeBorder(tint.ink.opacity(0.75), lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The cell renders only the day number, so VoiceOver would say "26" with
        // no month or year, and "selected" / "today" are fill-and-outline cues
        // with no text behind them.
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Formatting.locale)))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func dayColor(isSelected: Bool, isToday: Bool, inMonth: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return tint.ink }
        return inMonth ? .primary : .secondary.opacity(0.55)
    }
}

// MARK: - Grid math

/// The date arithmetic behind `MonthCalendar`, kept pure and separate so it can
/// be reasoned about (and tested) without a view.
enum MonthGrid {
    /// Midnight on the first of `date`'s month.
    static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Every cell of the month grid, including the leading and trailing days
    /// borrowed from the neighbouring months. Always `weeks` rows so the popover
    /// doesn't change height as you page between a 4-row and a 6-row month.
    static func days(for month: Date, calendar: Calendar, weeks: Int = 6) -> [Date] {
        let first = startOfMonth(for: month, calendar: calendar)
        let weekday = calendar.component(.weekday, from: first)
        // How many days of the previous month share the first row.
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// One-or-two letter weekday headers, rotated to start on the locale's first
    /// weekday.
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// "July 2026", in the app's language. The formatter is built per call:
    /// shared date formatters aren't safe under Swift 6 concurrency.
    static func title(for month: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Formatting.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        let text = formatter.string(from: month)
        // Some locales lowercase the month name; a heading reads better capped.
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
