import Foundation
import SwiftUI

/// A month grid that fills whatever width it is given.
///
/// `DatePicker(.graphical)` on macOS is an `NSDatePicker`, and that view has a
/// fixed 139×148 intrinsic size at *every* control size — it can't be asked to
/// fill a popover, and scaling it up just rasterizes the text. So the grid is
/// drawn here instead: it stays crisp at any size and can wear the app's tints.
///
/// Locale is respected throughout — the week starts on `Calendar.firstWeekday`
/// and the headers come from the calendar's own symbols.
struct MonthCalendar: View {
    @Binding var selection: Date
    /// Colour for the selected day's fill and today's marker.
    var accent: Color = Tint.blue.deep

    /// The month on screen, which the user can page away from the selection.
    @State private var visibleMonth: Date

    init(selection: Binding<Date>, accent: Color = Tint.blue.deep) {
        _selection = selection
        self.accent = accent
        _visibleMonth = State(
            initialValue: MonthGrid.startOfMonth(for: selection.wrappedValue, calendar: .current)
        )
    }

    private static let rowHeight: CGFloat = 28

    var body: some View {
        let calendar = Calendar.current

        VStack(spacing: 6) {
            header(calendar)
            weekdayRow(calendar)
            grid(calendar)
        }
        // Picking a date elsewhere (a preset pill) should bring its month up.
        .onChange(of: selection) { _, newValue in
            visibleMonth = MonthGrid.startOfMonth(for: newValue, calendar: .current)
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
            .foregroundStyle(accent)
            .padding(.horizontal, 4)
            .help("Jump to this month")
            stepButton(systemImage: "chevron.right", help: "Next month") { step(1, calendar) }
        }
    }

    private func stepButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
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
            Text(day, format: .dateTime.day())
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, inMonth: inMonth))
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
                // Cells are wider than they are tall, so a rounded rectangle
                // fits the shape better than the usual circle.
                .background {
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    if isSelected {
                        shape.fill(accent)
                    } else if isToday {
                        shape.strokeBorder(accent.opacity(0.55), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayColor(isSelected: Bool, isToday: Bool, inMonth: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return accent }
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

    /// "July 2026", localized. The formatter is built per call: shared date
    /// formatters aren't safe under Swift 6 concurrency.
    static func title(for month: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        let text = formatter.string(from: month)
        // Some locales lowercase the month name; a heading reads better capped.
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
