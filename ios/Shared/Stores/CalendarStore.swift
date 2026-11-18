import Foundation
import SwiftUI

// The Calendar module's logic, with no interface: the week or month on screen (Monday first, as the web),
// moving between them, the events in it by day, the open event, the connected calendars for the legend, and
// add / edit / delete. Dates are "YYYY-MM-DD" and times "HH:MM" text, as the server sends them, so nothing here
// depends on this Mac's time zone. The Mac screen is built on it. It talks to the server through
// `CalendarAPI`, so tests can use a stub.

/// A connected calendar (Google, CalDAV), for the legend under the grid
struct CalendarSourceInfo: Codable, Equatable, Identifiable {
    let name: String
    let color: String
    let lastSynced: Date?
    var id: String { name }
}

struct CalendarResponse: Decodable, Equatable {
    let from: String
    let days: Int
    let today: String
    let events: [CalendarEvent]
    /// Older servers don't send this; the legend and the notice then stay hidden
    let sources: [CalendarSourceInfo]?
}

/// A calendar an event can be added to (the web's "Calendar" choice)
struct CalendarChoice: Codable, Equatable, Identifiable {
    let value: String
    let label: String
    let color: String
    var id: String { value }
}

struct CalendarChoices: Decodable, Equatable {
    let calendars: [CalendarChoice]
    let defaultTarget: String
}

struct EventDraft: Equatable {
    var title = ""
    var date = ""
    var allDay = false
    var startTime = "09:00"
    var endTime = "10:00"
    var location = ""
    var description = ""
    /// New events only: which calendar
    var calendarTarget = "local"

    init() {}
    init(date: String, calendarTarget: String = "local") { self.date = date; self.calendarTarget = calendarTarget }

    /// What the form shows for an event you made: its own fields (the old "[vT]" marker is dropped, as the web does)
    init(_ e: CalendarEvent) {
        title = e.title
        date = e.day
        allDay = e.allDay
        startTime = e.startTime ?? "09:00"
        endTime = e.endTime ?? "10:00"
        location = e.location ?? ""
        description = CalendarStore.cleanNotes(e.description)
    }
}

@MainActor
protocol CalendarAPI {
    func events(from: String, days: Int) async throws -> CalendarResponse
    func choices() async throws -> CalendarChoices
    func create(_ draft: EventDraft) async throws
    func update(id: Int, _ draft: EventDraft) async throws
    func delete(id: Int) async throws
}

@MainActor
struct LiveCalendarAPI: CalendarAPI {
    private var api: APIClient { .shared }

    private func body(_ d: EventDraft) -> [String: Any] {
        ["title": d.title, "date": d.date, "allDay": d.allDay, "startTime": d.startTime, "endTime": d.endTime,
         "location": d.location, "description": d.description]
    }

    func events(from: String, days: Int) async throws -> CalendarResponse {
        try await api.get("/calendar", query: ["from": from, "days": String(days)])
    }
    func choices() async throws -> CalendarChoices { try await api.get("/calendar/calendars") }
    func create(_ d: EventDraft) async throws {
        var b = body(d); b["calendarTarget"] = d.calendarTarget
        try await api.post("/calendar/events", b)
    }
    func update(id: Int, _ d: EventDraft) async throws { try await api.post("/calendar/events/\(id)", body(d), method: "PUT") }
    func delete(id: Int) async throws { try await api.delete("/calendar/events/\(id)") }
}

enum CalendarViewMode: String, CaseIterable { case week, month }

/// Date arithmetic on "YYYY-MM-DD" text (Gregorian, no time zone involved)
enum CalendarMath {
    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func date(_ ymd: String) -> Date? { Fmt.day(ymd) }
    static func string(_ d: Date) -> String { Fmt.ymd(d, in: TimeZone(identifier: "UTC")!) }

    static func addDays(_ ymd: String, _ n: Int) -> String {
        guard let d = date(ymd), let r = cal.date(byAdding: .day, value: n, to: d) else { return ymd }
        return string(r)
    }

    static func addMonths(_ ymd: String, _ n: Int) -> String {
        guard let d = date(ymd), let r = cal.date(byAdding: .month, value: n, to: d) else { return ymd }
        return string(r)
    }

    /// Monday = 0 … Sunday = 6
    static func weekdayIndex(_ ymd: String) -> Int {
        guard let d = date(ymd) else { return 0 }
        return (cal.component(.weekday, from: d) + 5) % 7
    }

    static func monday(of ymd: String) -> String { addDays(ymd, -weekdayIndex(ymd)) }
    static func firstOfMonth(_ ymd: String) -> String { String(ymd.prefix(7)) + "-01" }

    static func daysInMonth(_ ymd: String) -> Int {
        guard let d = date(ymd), let r = cal.range(of: .day, in: .month, for: d) else { return 30 }
        return r.count
    }

    static func dayNumber(_ ymd: String) -> Int { Int(ymd.suffix(2)) ?? 0 }
    static func sameMonth(_ a: String, _ b: String) -> Bool { a.prefix(7) == b.prefix(7) }
}

@MainActor @Observable
final class CalendarStore {
    private let api: CalendarAPI

    private(set) var mode: CalendarViewMode = .week
    /// Any day inside what is shown
    private(set) var anchor: String
    private(set) var today: String
    private(set) var events: [CalendarEvent] = []
    private(set) var sources: [CalendarSourceInfo] = []
    /// False until the server has said (older servers never do), so the notice isn't shown by mistake
    private(set) var sourcesKnown = false
    private(set) var loaded = false
    private(set) var choices: [CalendarChoice] = []
    private(set) var defaultTarget = "local"
    /// The event in the right pane
    private(set) var selectedID: Int?
    var error: String?

    init(api: CalendarAPI, today: String = Fmt.ymd(.now)) {
        self.api = api
        self.today = today
        self.anchor = today
    }
    convenience init(today: String = Fmt.ymd(.now)) { self.init(api: LiveCalendarAPI(), today: today) }

    // ── What is shown ───────────────────────────────────────────────────────

    /// The first day shown: the Monday of the week, or of the week the month starts in
    var rangeStart: String {
        mode == .week ? CalendarMath.monday(of: anchor) : CalendarMath.monday(of: CalendarMath.firstOfMonth(anchor))
    }

    /// Weeks in the grid: one for the week view; the month view only as many as the month needs (4 to 6)
    var weekCount: Int {
        if mode == .week { return 1 }
        let lead = CalendarMath.weekdayIndex(CalendarMath.firstOfMonth(anchor))
        return Int((Double(lead + CalendarMath.daysInMonth(anchor)) / 7).rounded(.up))
    }

    var dayCount: Int { weekCount * 7 }
    var rangeEnd: String { CalendarMath.addDays(rangeStart, dayCount - 1) }

    /// The days of week `index` (0 for the week view)
    func days(inWeek index: Int) -> [String] {
        (0..<7).map { CalendarMath.addDays(rangeStart, index * 7 + $0) }
    }

    /// The heading: "Nov 9 – Nov 15, 2026" for a week, "November 2026" for a month (as the web)
    var rangeLabel: String {
        switch mode {
        case .month:
            guard let d = CalendarMath.date(CalendarMath.firstOfMonth(anchor)) else { return anchor }
            return Self.format(d, "MMMM yyyy")
        case .week:
            guard let a = CalendarMath.date(rangeStart), let b = CalendarMath.date(rangeEnd) else { return anchor }
            return Self.format(a, "MMM d") + " – " + Self.format(b, "MMM d, yyyy")
        }
    }

    fileprivate static func format(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f.string(from: d)
    }

    func isToday(_ day: String) -> Bool { day == today }
    /// Days outside the month are faded in the month view
    func isInMonth(_ day: String) -> Bool { mode == .week || CalendarMath.sameMonth(day, anchor) }

    /// The day's events, earliest first (as the web)
    func events(on day: String) -> [CalendarEvent] {
        events.filter { $0.day == day }.sorted { $0.startAt < $1.startAt }
    }

    /// No calendar is connected: the web's amber notice. Only when the server said so.
    var showsNoCalendarsNotice: Bool { loaded && sourcesKnown && sources.isEmpty }

    var selected: CalendarEvent? { selectedID.flatMap { id in events.first { $0.id == id } } }

    // ── Moving ──────────────────────────────────────────────────────────────

    func setMode(_ m: CalendarViewMode) async {
        guard m != mode else { return }
        mode = m
        await load()
    }

    func previous() async { await move(by: -1) }
    func next() async { await move(by: 1) }

    private func move(by step: Int) async {
        anchor = mode == .week ? CalendarMath.addDays(anchor, 7 * step) : CalendarMath.addMonths(CalendarMath.firstOfMonth(anchor), step)
        await load()
    }

    func goToToday() async { await show(day: today) }

    /// Shows the week or month that has this day
    func show(day: String) async {
        anchor = day
        await load()
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        do {
            let r = try await api.events(from: rangeStart, days: dayCount)
            events = r.events
            today = r.today
            if let s = r.sources { sources = s; sourcesKnown = true }
            loaded = true; error = nil
            if let id = selectedID, !events.contains(where: { $0.id == id }) { selectedID = nil }
        } catch { self.error = error.localizedDescription }
    }

    /// The Calendar choices for a new event (once); the first try again if it failed
    func loadChoices() async {
        guard choices.isEmpty else { return }
        do {
            let c = try await api.choices()
            choices = c.calendars; defaultTarget = c.defaultTarget
        } catch { self.error = "Couldn't load your calendars. \(error.localizedDescription)" }
    }

    // ── The open event ──────────────────────────────────────────────────────

    func select(_ id: Int?) { selectedID = id }

    /// Opens an event that may be outside what is shown (Today's events): goes to its week, then selects it
    func open(_ event: CalendarEvent) async {
        if !events.contains(where: { $0.id == event.id }) { await show(day: event.day) }
        selectedID = events.contains(where: { $0.id == event.id }) ? event.id : nil
    }

    // ── Add, edit, delete ───────────────────────────────────────────────────

    /// The same checks the server makes, so the form can say so before asking
    static func problem(with d: EventDraft) -> String? {
        if d.title.trimmingCharacters(in: .whitespaces).isEmpty { return "Title is required." }
        if d.date.isEmpty { return "Date is required." }
        if !d.allDay, !d.endTime.isEmpty, d.endTime < d.startTime { return "The event ends before it starts." }
        return nil
    }

    /// Creates the event, shows the week or month it is in, and returns it (the server doesn't say which it made,
    /// so it is the newest with this title on that day)
    @discardableResult
    func add(_ draft: EventDraft) async -> CalendarEvent? {
        if let p = Self.problem(with: draft) { error = p; return nil }
        var d = draft; d.title = d.title.trimmingCharacters(in: .whitespaces)
        do {
            try await api.create(d)
            if rangeStart > d.date || rangeEnd < d.date { anchor = d.date }
            await load()
            let made = events.filter { $0.title == d.title && $0.day == d.date }.max { $0.id < $1.id }
            selectedID = made?.id
            return made
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Saves an event you made. The grid follows it if the date moved to another week or month.
    @discardableResult
    func update(_ id: Int, _ draft: EventDraft) async -> Bool {
        if let p = Self.problem(with: draft) { error = p; return false }
        var d = draft; d.title = d.title.trimmingCharacters(in: .whitespaces)
        do {
            try await api.update(id: id, d)
            if rangeStart > d.date || rangeEnd < d.date { anchor = d.date }
            await load()
            selectedID = events.contains(where: { $0.id == id }) ? id : nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ id: Int) async {
        do {
            try await api.delete(id: id)
            events.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    // ── Text for an event ───────────────────────────────────────────────────

    /// Notes without the old "[vT]" marker some imported events start with
    static func cleanNotes(_ s: String?) -> String {
        guard var t = s else { return "" }
        if t.hasPrefix("[vT]") { t = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        return t
    }

    /// "Saturday, November 14, 2026"
    static func longDate(_ ymd: String) -> String {
        guard let d = CalendarMath.date(ymd) else { return ymd }
        return format(d, "EEEE, MMMM d, yyyy")
    }

    /// "9:00 AM – 10:00 AM", or "All day"
    static func timeText(_ e: CalendarEvent, hour12: Bool) -> String {
        guard !e.allDay, let s = e.startTime else { return "All day" }
        let end = e.endTime.map { " – " + Fmt.time($0, hour12: hour12) } ?? ""
        return Fmt.time(s, hour12: hour12) + end
    }

    /// Only http and https addresses are opened, as the web does
    static func isWebLink(_ s: String?) -> Bool {
        guard let s, let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
