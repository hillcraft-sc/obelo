import Foundation
import SwiftUI

// The Analytics module's logic, with no interface: the loaded numbers, the 30d / 90d / All time choice, and
// the sentences and colour bands the web page works out in its own code. The Mac screen is built on it.
// It talks to the server through `AnalyticsAPI`, so tests can use a stub.

@MainActor
protocol AnalyticsAPI {
    func load(range: String) async throws -> Analytics
}

@MainActor
struct LiveAnalyticsAPI: AnalyticsAPI {
    func load(range: String) async throws -> Analytics {
        try await APIClient.shared.get("/analytics", query: ["range": range])
    }
}

enum AnalyticsRange: String, CaseIterable {
    case days30 = "30", days90 = "90", all
    var label: String {
        switch self {
        case .days30: "30d"
        case .days90: "90d"
        case .all: "All time"
        }
    }
}

/// How good a rate is, as the web colours it: 80 and over is good, 50 and over is fair, below that is low
enum RateBand: Equatable {
    case none, good, fair, low
    init(_ rate: Int?) {
        guard let rate else { self = .none; return }
        self = rate >= 80 ? .good : rate >= 50 ? .fair : .low
    }
}

extension Analytics.Week {
    static let buckets: [(key: String, label: String)] = [
        ("early", "Early"), ("on_time", "On time"), ("late_same_day", "Same-day late"),
        ("late_1_3", "Late 1–3d"), ("late_4_7", "Late 4–7d"), ("late_8plus", "Late 8+d"),
    ]
}

@MainActor @Observable
final class AnalyticsStore {
    private let api: AnalyticsAPI

    private(set) var data: Analytics?
    private(set) var loaded = false
    var error: String?
    private(set) var range: AnalyticsRange

    private static let rangeKey = "analyticsRange"

    init(api: AnalyticsAPI, range: AnalyticsRange? = nil) {
        self.api = api
        self.range = range ?? AnalyticsRange(rawValue: UserDefaults.standard.string(forKey: Self.rangeKey) ?? "") ?? .days30
    }
    convenience init() { self.init(api: LiveAnalyticsAPI()) }

    /// Loads the numbers for the chosen range. What is on screen stays until the new numbers arrive; a failure keeps it too.
    func load() async {
        let asked = range
        do {
            let d = try await api.load(range: asked.rawValue)
            guard asked == range else { return }   // the choice changed while this was loading
            data = d; loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Changes the range, remembers it, and loads again
    func setRange(_ r: AnalyticsRange) async {
        guard r != range else { return }
        range = r
        UserDefaults.standard.set(r.rawValue, forKey: Self.rangeKey)
        await load()
    }

    // ── What the page says ──────────────────────────────────────────────────

    var findings: [Analytics.Finding] { data?.standsOut ?? [] }
    var findingsByAI: Bool { data?.standsOutByAi == true }

    /// "Analytics improve with more data": between 1 and 4 completions
    var showsSmallSampleNotice: Bool { (data?.summary.total).map { $0 > 0 && $0 < 5 } ?? false }
    var smallSampleText: String {
        let n = data?.summary.total ?? 0
        return "Analytics improve with more data — you have \(n) completion\(n == 1 ? "" : "s") in this period. Percentages are based on a small sample."
    }

    var hasTimingData: Bool { data?.weeklyData.contains { $0.total > 0 } ?? false }

    /// The italic sentence under "Completion Timing" (the web's `chartNarrative`)
    var timingNarrative: String? {
        guard let w = data?.weeklyData else { return nil }
        let n = w.reduce(0) { $0 + $1.total }
        guard n > 0 else { return nil }
        let onTime = w.reduce(0) { $0 + $1.early + $1.on_time }
        let sdLate = w.reduce(0) { $0 + $1.late_same_day }
        let daysLate = n - onTime - sdLate
        let all = n == 1 ? "Your one completion was" : n == 2 ? "Both completions were" : "All \(n) completions were"
        let pct = { (x: Int) in Int((Double(x) / Double(n) * 100).rounded()) }
        let items = { (x: Int) in "\(x) \(x == 1 ? "item was" : "items were")" }
        if onTime == n { return "\(all) on time or early this period." }
        if sdLate == n { return "\(all) same-day late — you hit the right day but missed the due time by more than 30 minutes." }
        if daysLate == n { return "\(all) finished days after the due date." }
        if onTime >= sdLate && onTime >= daysLate {
            return "\(pct(onTime))% of completions were on time or early (\(onTime) of \(n))." + (daysLate > 0 ? " \(items(daysLate)) days late." : "")
        }
        if sdLate >= daysLate {
            return "\(pct(sdLate))% of completions were same-day late — right day, but past the due time." + (daysLate > 0 ? " \(items(daysLate)) days late." : "")
        }
        return "\(pct(daysLate))% of completions were finished days after their due date (\(daysLate) of \(n))." + (onTime > 0 ? " \(items(onTime)) on time or early." : "")
    }

    /// "↑ trending up", "↓ trending down" or "→ steady"
    var velocityLabel: String {
        switch data?.velocityTrend {
        case "up": "↑ trending up"
        case "down": "↓ trending down"
        default: "→ steady"
        }
    }
    var velocityBand: RateBand { data?.velocityTrend == "up" ? .good : data?.velocityTrend == "down" ? .low : .none }

    /// Priorities with at least one item, in the server's order
    var priorities: [Analytics.Priority] { data?.priorityData.filter { $0.total > 0 } ?? [] }

    // ── Wording for single items ────────────────────────────────────────────

    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    static func frequencyLabel(_ f: String) -> String {
        ["daily": "Daily", "weekdays": "Weekdays", "weekends": "Weekends", "weekly": "Weekly", "custom": "Custom"][f] ?? f
    }

    /// "Nov 3" from the server's "YYYY-MM-DD…" date (read as UTC, as the web does)
    static func shortDate(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return iso }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[parts[1] - 1]) \(parts[2])"
    }

    /// The small lines under a routine's name, as the web's `_si` list, each with its tone
    struct RoutineNote: Equatable { enum Tone { case streak, muted, broke, rate(RateBand), faint }; let text: String; let tone: Tone
        static func == (a: RoutineNote, b: RoutineNote) -> Bool { a.text == b.text }
    }
    static func notes(for r: Analytics.RoutineStats.Item) -> [RoutineNote] {
        var out: [RoutineNote] = []
        if r.streakCurrent > 0 {
            var t = "🔥 \(r.streakCurrent)d streak"
            if r.streakBest > r.streakCurrent { t += " · best \(r.streakBest)d" }
            out.append(RoutineNote(text: t, tone: .streak))
        } else if r.streakBest > 0 {
            out.append(RoutineNote(text: "best \(r.streakBest)d", tone: .muted))
        }
        if r.streakCount > 0 {
            out.append(RoutineNote(text: "\(plural(r.streakCount, "streak")) · avg \(r.streakAvg)d", tone: .faint))
        }
        if r.streakCurrent == 0, let b = r.lastBroken {
            out.append(RoutineNote(text: "broke \(b.length)d · \(shortDate(b.endDate))", tone: .broke))
        }
        if let time = r.specificTime, let rate = r.specificTimeRate {
            var t = "on time at \(time): \(rate)%"
            if r.timedSampleSize < 5 { t += " (\(r.timedSampleSize) logged)" }
            out.append(RoutineNote(text: t, tone: .rate(RateBand(rate))))
        }
        return out
    }

    /// "9d (Oct 1–Oct 9 ▶)" for each of the routine's best streaks; only when it has more than one
    static func topStreakText(_ r: Analytics.RoutineStats.Item) -> String? {
        guard let top = r.topStreaks, top.count > 1 else { return nil }
        return top.map { "\($0.length)d (\(shortDate($0.startDate))–\(shortDate($0.endDate))\($0.isActive ? " ▶" : ""))" }.joined(separator: " · ")
    }
}
