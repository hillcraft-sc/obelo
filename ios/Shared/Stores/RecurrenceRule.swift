import Foundation

/// The repeat rule string the server and the web form use: a fixed word ("daily", "weekdays", …) or
/// "custom:<freq>:<every>[:each:<day> | :onthe:<ordinal>:<weekday>]" (src/lib/recurrence.js, views/tasks/form.ejs).
struct RecurrenceRule: Equatable {
    enum Frequency: String, CaseIterable { case daily, weekly, monthly, yearly
        var unit: String { switch self { case .daily: "days"; case .weekly: "weeks"; case .monthly: "months"; case .yearly: "years" } }
        var label: String { rawValue.capitalized }
    }
    enum MonthMode: Equatable { case each(day: Int), onThe(ordinal: String, weekday: String) }

    static let ordinals = ["first", "second", "third", "fourth", "last"]
    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let presets: [(String, String)] = Fmt.recurRules

    /// A fixed choice, or nil when the rule is custom
    var preset: String?
    var frequency: Frequency = .daily
    var every: Int = 1
    var monthMode: MonthMode = .each(day: 1)

    var isCustom: Bool { preset == nil }

    init(preset: String = "daily") { self.preset = preset }

    init(custom frequency: Frequency, every: Int = 1, monthMode: MonthMode = .each(day: 1)) {
        self.preset = nil; self.frequency = frequency; self.every = max(1, min(99, every)); self.monthMode = monthMode
    }

    /// Reads a stored rule. Anything unknown is kept as a custom daily rule rather than lost.
    init(_ raw: String?) {
        guard let raw, !raw.isEmpty else { self.init(preset: "daily"); return }
        if Self.presets.contains(where: { $0.0 == raw }) { self.init(preset: raw); return }
        let p = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard p.first == "custom", p.count >= 3, let f = Frequency(rawValue: p[1]) else {
            self.init(custom: .daily); return
        }
        var mode = MonthMode.each(day: 1)
        if f == .monthly, p.count >= 5 {
            if p[3] == "onthe", p.count >= 6 { mode = .onThe(ordinal: p[4], weekday: p[5]) }
            else if p[3] == "each" { mode = .each(day: Int(p[4]) ?? 1) }
        }
        self.init(custom: f, every: Int(p[2]) ?? 1, monthMode: mode)
    }

    var raw: String {
        if let preset { return preset }
        var s = "custom:\(frequency.rawValue):\(every)"
        if frequency == .monthly {
            switch monthMode {
            case .each(let day): s += ":each:\(day)"
            case .onThe(let o, let w): s += ":onthe:\(o):\(w)"
            }
        }
        return s
    }
}
