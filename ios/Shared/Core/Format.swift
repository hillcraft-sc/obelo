import Foundation

// Text formatting that matches the web app's output.

enum Fmt {
    private static let utc = TimeZone(identifier: "UTC")!

    /// "YYYY-MM-DD" → Date at UTC midnight (how the server stores due dates)
    static func day(_ ymd: String?) -> Date? {
        guard let ymd else { return nil }
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func ymd(_ date: Date, in tz: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func format(_ date: Date, _ pattern: String, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "Oct 10" — toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
    static func shortDay(_ ymd: String?) -> String {
        guard let d = day(ymd) else { return "" }
        return format(d, "MMM d", tz: utc)
    }

    /// "Saturday, October 10"
    static func longDay(_ ymd: String) -> String {
        guard let d = day(ymd) else { return ymd }
        return format(d, "EEEE, MMMM d", tz: utc)
    }

    static func weekdayShort(_ ymd: String) -> String {
        guard let d = day(ymd) else { return ymd }
        return format(d, "EEE, MMM d", tz: utc)
    }

    /// "HH:MM" → "5:00 PM" (or unchanged in 24h mode), like fmtHHMM in lib/timeFormat.js
    static func time(_ hhmm: String?, hour12: Bool) -> String {
        guard let hhmm, !hhmm.isEmpty else { return "" }
        guard hour12 else { return hhmm }
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return hhmm }
        let h12 = p[0] % 12 == 0 ? 12 : p[0] % 12
        return String(format: "%d:%02d %@", h12, p[1], p[0] >= 12 ? "PM" : "AM")
    }

    /// "Oct 10 · 5:00 PM"
    static func due(_ ymd: String?, _ hhmm: String?, hour12: Bool) -> String {
        [shortDay(ymd), time(hhmm, hour12: hour12)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func clock(_ date: Date, hour12: Bool, tz: TimeZone) -> String {
        format(date, hour12 ? "h:mm a" : "HH:mm", tz: tz)
    }

    static func monthDayYear(_ date: Date) -> String {
        format(date, "MMMM d, yyyy", tz: .current)
    }

    static func monthDay(_ date: Date) -> String {
        format(date, "MMM d", tz: .current)
    }

    static func hhmm(from date: Date) -> String {
        format(date, "HH:mm", tz: .current)
    }

    static func date(fromHHMM hhmm: String?) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let p = (hhmm ?? "09:00").split(separator: ":").compactMap { Int($0) }
        c.hour = p.first ?? 9
        c.minute = p.count > 1 ? p[1] : 0
        return Calendar.current.date(from: c) ?? .now
    }

    /// Local calendar date ↔ "YYYY-MM-DD" for date pickers
    static func localDate(_ ymd: String?) -> Date {
        guard let ymd else { return .now }
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return .now }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) ?? .now
    }

    static let statusLabels: [String: String] = [
        "inbox": "Inbox", "today": "Today", "in-progress": "In Progress", "done": "Done", "archived": "Archived",
    ]
    static let statuses = ["inbox", "today", "in-progress", "done", "archived"]

    static let priorities = ["none", "low", "medium", "high"]
    static func priorityLabel(_ p: String) -> String { p.prefix(1).uppercased() + p.dropFirst() }

    static let timeOfDay = ["morning", "afternoon", "evening", "anytime"]
    static let timeLabels = ["morning": "Morning", "afternoon": "Afternoon", "evening": "Evening", "anytime": "Anytime"]
    static let freqLabels = ["daily": "Daily", "weekdays": "Weekdays", "weekends": "Weekends", "weekly": "Weekly", "custom": "Custom"]
    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static let recurRules: [(String, String)] = [
        ("hourly", "Hourly"), ("daily", "Daily"), ("weekdays", "Weekdays"), ("weekends", "Weekends"),
        ("weekly", "Weekly"), ("biweekly", "Biweekly"), ("monthly", "Monthly"),
        ("every3months", "Every 3 Months"), ("every6months", "Every 6 Months"), ("yearly", "Yearly"),
    ]
    static func recurLabel(_ rule: String?) -> String {
        guard let rule else { return "" }
        return recurRules.first { $0.0 == rule }?.1 ?? rule
    }

    static let reminderOffsets: [(Int, String)] = [
        (0, "At the due time"), (15, "15 minutes before"), (30, "30 minutes before"), (60, "1 hour before"),
    ]

    static let noteTypeLabels = ["note": "Note", "journal": "Journal", "quote": "Quote"]

    static func tagsText(_ tags: [String]) -> String { tags.joined(separator: ", ") }
    static func tags(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
