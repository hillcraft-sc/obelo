import SwiftUI

// The calendar grid (web: calendar/index.ejs): seven columns Monday to Sunday, either one week with
// each day's events as chips, or a month of boxes with up to three chips a day and "+N more". Also the
// small dot in a calendar's colour.

/// A coloured dot (the calendar an event is on, the legend)
struct KitColorDot: View {
    let hex: String
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(Color(hex: hex)).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// One event as the grid draws it
struct KitCalendarChip: Identifiable, Equatable {
    let id: Int
    let title: String
    /// "9:00 AM", nil for all-day events
    let time: String?
    let color: String
}

/// One day as the grid draws it
struct KitCalendarDay: Identifiable, Equatable {
    /// "YYYY-MM-DD"
    let id: String
    let number: Int
    let isToday: Bool
    /// False for the faded days that belong to the month before or after
    let inMonth: Bool
    let chips: [KitCalendarChip]
    /// "Saturday, November 14" for VoiceOver and the tooltip
    let longName: String
}

struct KitCalendarGrid<EventMenu: View, DayMenu: View>: View {
    @Environment(\.theme) private var theme
    let isMonth: Bool
    /// The weeks to draw: one for the week view, four to six for a month
    let weeks: [[KitCalendarDay]]
    let selectedEvent: Int?
    /// A click on an event, and a double-click on it
    let onEvent: (Int) -> Void
    let onOpenEvent: (Int) -> Void
    /// A click on a day's number, and a double-click on an empty part of the day: start an event there
    let onDay: (String) -> Void
    @ViewBuilder let eventMenu: (Int) -> EventMenu
    @ViewBuilder let dayMenu: (String) -> DayMenu

    private static var names: [String] { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] }

    var body: some View {
        if isMonth { month } else { week }
    }

    // ── Week ────────────────────────────────────────────────────────────────

    private var week: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array((weeks.first ?? []).enumerated()), id: \.element.id) { i, day in
                VStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text(Self.names[i]).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(day.isToday ? theme.accentText : theme.textMuted)
                        KitDayNumber(day: day, size: 32) { onDay(day.id) }
                    }
                    .padding(.bottom, 8)
                    VStack(spacing: 4) {
                        ForEach(day.chips) { chip in
                            KitEventChip(chip: chip, compact: false, selected: selectedEvent == chip.id,
                                         onClick: { onEvent(chip.id) }, onOpen: { onOpenEvent(chip.id) })
                                .contextMenu { eventMenu(chip.id) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
                    .overlay(alignment: .top) { KitDivider() }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onDay(day.id) }
                    .contextMenu { dayMenu(day.id) }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(day.longName)
            }
        }
    }

    // ── Month ───────────────────────────────────────────────────────────────

    private var month: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Self.names, id: \.self) { n in
                    Text(n).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { wi, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { ci, day in
                            cell(day)
                                .overlay(alignment: .trailing) { if ci < 6 { Rectangle().fill(theme.border1).frame(width: 1) } }
                        }
                    }
                    .overlay(alignment: .bottom) { if wi < weeks.count - 1 { KitDivider() } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border1))
        }
    }

    private func cell(_ day: KitCalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            KitDayNumber(day: day, size: 28) { onDay(day.id) }
            ForEach(day.chips.prefix(3)) { chip in
                KitEventChip(chip: chip, compact: true, selected: selectedEvent == chip.id,
                             onClick: { onEvent(chip.id) }, onOpen: { onOpenEvent(chip.id) })
                    .contextMenu { eventMenu(chip.id) }
            }
            if day.chips.count > 3 {
                Text("+\(day.chips.count - 3) more").font(.system(size: 10)).foregroundStyle(theme.textMuted).padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .opacity(day.inMonth ? 1 : 0.3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDay(day.id) }
        .contextMenu { dayMenu(day.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.longName)
    }
}

/// A day's number: a plain circle that starts a new event on that day, filled for today
private struct KitDayNumber: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let day: KitCalendarDay
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(day.number)")
                .font(.system(size: 14, weight: day.isToday ? .bold : .semibold))
                .foregroundStyle(day.isToday ? theme.onAccent : hovering ? theme.textPrimary : theme.text400)
                .frame(width: size, height: size)
                .background(day.isToday ? theme.accent : hovering ? theme.elevated : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New event on \(day.longName)")
        .accessibilityLabel("New event on \(day.longName)")
    }
}

/// An event in the grid. Week: the time above the title, with a coloured left edge. Month: one line.
struct KitEventChip: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let chip: KitCalendarChip
    let compact: Bool
    let selected: Bool
    let onClick: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let colour = Color(hex: chip.color)
        Group {
            if compact {
                Text((chip.time.map { $0 + " " } ?? "") + chip.title)
                    .font(.system(size: 10)).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let t = chip.time { Text(t).font(.system(size: 10)).opacity(0.75) }
                    Text(chip.title).font(.system(size: 12, weight: .medium))
                }
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
        .foregroundStyle(colour)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colour.opacity(compact ? 0.19 : 0.125), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(alignment: .leading) { if !compact { Rectangle().fill(colour).frame(width: 3) } }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(selected ? theme.accent : .clear, lineWidth: 2))
        .opacity(hovering && !selected ? 0.85 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onClick() }
        .help(chip.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((chip.time.map { $0 + ", " } ?? "All day, ") + chip.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
