import SwiftUI

// The Routines module's logic, with no interface: the three tabs, the tag filter, the Today grouping,
// selection, the open routine with its heatmap and weekly bars, create / edit, mark done today,
// archive / restore / delete and the bulk actions. The Mac screen is built on it. It talks to the
// server through `RoutinesAPI`, so tests can use a stub.

struct RoutinesListResponse: Decodable, Equatable {
    let routines: [Routine]
    let tags: [String]
}

struct RoutineDetail: Decodable, Equatable {
    let routine: Routine
    let heatmap: [[HeatmapDay]]
    let weeklyStats: [WeeklyStat]
}

/// Every field of a routine the detail pane edits. Sent whole on each save, like the web form.
/// A routine needs a title (`isComplete`).
struct RoutineDraft: Equatable {
    var title = ""
    var description = ""
    var timeOfDay = "anytime"
    /// "HH:mm", or empty for no specific time
    var specificTime = ""
    var frequency = "daily"
    var scheduleDays: [String] = []
    /// nil means ongoing; a number means time-limited (the routine archives itself when it is reached)
    var durationDays: Int?
    /// "yyyy-MM-dd", or empty
    var startDate = ""
    var tags: [String] = []
    var notify = false

    init() {}
    init(_ r: Routine) {
        title = r.title; description = r.description; timeOfDay = r.timeOfDay; specificTime = r.specificTime ?? ""
        frequency = r.frequency; scheduleDays = r.scheduleDays; durationDays = r.durationDays
        startDate = r.startDate ?? ""; tags = r.tags; notify = r.notify
    }

    var isComplete: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    var usesDays: Bool { frequency == "weekly" || frequency == "custom" }

    var body: [String: Any] {
        ["title": title, "description": description, "timeOfDay": timeOfDay, "specificTime": specificTime,
         "frequency": frequency, "scheduleDays": usesDays ? scheduleDays : [String](),
         "durationDays": durationDays.map { $0 as Any } ?? NSNull(), "startDate": durationDays == nil ? "" : startDate,
         "tags": tags, "notify": notify]
    }
}

@MainActor
protocol RoutinesAPI {
    func list(view: String, tag: String?) async throws -> RoutinesListResponse
    func detail(id: Int) async throws -> RoutineDetail
    func create(_ body: [String: Any]) async throws -> Routine
    func update(id: Int, _ body: [String: Any]) async throws -> Routine
    /// Toggles today's completion and returns the routine with its new streak
    func complete(id: Int) async throws -> Routine
    /// Toggles archived
    func archive(id: Int) async throws
    func delete(id: Int) async throws
    /// Returns how many routines the server changed
    func bulk(action: String, ids: [Int]) async throws -> Int
    func allTags() async throws -> [String]
}

@MainActor
struct LiveRoutinesAPI: RoutinesAPI {
    private var api: APIClient { .shared }
    private struct One: Decodable { let routine: Routine }
    private struct Count: Decodable { let count: Int }
    private struct Tags: Decodable { let tags: [String] }

    func list(view: String, tag: String?) async throws -> RoutinesListResponse {
        try await api.get("/routines", query: ["view": view, "tag": tag])
    }
    func detail(id: Int) async throws -> RoutineDetail { try await api.get("/routines/\(id)") }
    func create(_ body: [String: Any]) async throws -> Routine { (try await api.post("/routines", body) as One).routine }
    func update(id: Int, _ body: [String: Any]) async throws -> Routine {
        (try await api.post("/routines/\(id)", body, method: "PUT") as One).routine
    }
    func complete(id: Int) async throws -> Routine { (try await api.post("/routines/\(id)/complete") as One).routine }
    func archive(id: Int) async throws { try await api.post("/routines/\(id)/archive") }
    func delete(id: Int) async throws { try await api.delete("/routines/\(id)") }
    func bulk(action: String, ids: [Int]) async throws -> Int {
        (try await api.post("/routines/bulk", ["action": action, "ids": ids]) as Count).count
    }
    func allTags() async throws -> [String] { (try await api.get("/tags") as Tags).tags }
}

@MainActor @Observable
final class RoutinesStore {
    static let views = ["today", "all", "archived"]
    static let timesOfDay = ["morning", "afternoon", "evening", "anytime"]
    static let timeLabels = ["morning": "Morning", "afternoon": "Afternoon", "evening": "Evening", "anytime": "Anytime"]
    static let frequencies = ["daily", "weekdays", "weekends", "weekly", "custom"]
    static let frequencyChoiceLabels = ["daily": "Daily", "weekdays": "Weekdays (Mon–Fri)", "weekends": "Weekends",
                                        "weekly": "Weekly (pick a day)", "custom": "Custom days"]

    private let api: RoutinesAPI

    var view = "today"
    var tag: String?
    private(set) var routines: [Routine] = []
    private(set) var tagList: [String] = []
    private(set) var loaded = false
    var error: String?

    /// Ticked or ⌘/⇧-clicked rows. One id shows that routine in the detail pane.
    var selection: Set<Int> = []
    /// The routine in the detail pane, when exactly one row is selected
    private(set) var open: RoutineDetail?
    private(set) var allTags: [String] = []

    init(api: RoutinesAPI) { self.api = api }
    convenience init() { self.init(api: LiveRoutinesAPI()) }

    var isFiltered: Bool { tag != nil }

    // ── What's on screen ────────────────────────────────────────────────────

    /// Today tab: the routines due today under Morning, Afternoon, Evening and Anytime (empty groups left out)
    var dueGroups: [(timeOfDay: String, routines: [Routine])] {
        Self.timesOfDay.compactMap { tod in
            let rows = routines.filter { $0.dueToday && $0.timeOfDay == tod }
            return rows.isEmpty ? nil : (timeOfDay: tod, routines: rows)
        }
    }

    /// Today tab: the ones not scheduled today (shown dimmed)
    var notDueToday: [Routine] { routines.filter { !$0.dueToday } }

    /// Archived tab: routines that reached their goal
    var completedStreaks: [Routine] { view == "archived" ? routines.filter { $0.finishedChallenge == true } : [] }

    /// The rows in the order shown, for ↑ ↓ and ⇧-click
    var displayedIDs: [Int] {
        view == "today" ? dueGroups.flatMap { $0.routines.map(\.id) } + notDueToday.map(\.id) : routines.map(\.id)
    }

    /// Nothing at all to show on this tab (before any filter message)
    var isEmpty: Bool { routines.isEmpty }
    var dueTodayIsEmpty: Bool { view == "today" && dueGroups.isEmpty }

    // ── List ────────────────────────────────────────────────────────────────

    func load() async {
        do {
            let r = try await api.list(view: view == "archived" ? "archived" : "today", tag: tag)
            routines = r.routines; tagList = r.tags; loaded = true; error = nil
            selection = selection.filter { id in r.routines.contains { $0.id == id } }
            if selection.count != 1 { open = nil }
        } catch { self.error = error.localizedDescription }
    }

    func show(view: String) async { self.view = view; selection = []; open = nil; await load() }
    func toggleTag(_ t: String) async { tag = (tag == t) ? nil : t; await load() }
    func clearFilter() async { tag = nil; await load() }

    // ── One routine ─────────────────────────────────────────────────────────

    func select(_ ids: Set<Int>) async {
        selection = ids
        guard ids.count == 1, let id = ids.first else { open = nil; return }
        await openRoutine(id)
    }

    func openRoutine(_ id: Int) async {
        do {
            let d = try await api.detail(id: id)
            guard selection == [id] else { return }   // the person moved on while it loaded
            open = d
            if allTags.isEmpty { allTags = (try? await api.allTags()) ?? [] }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// One routine from the server, without opening it (to find out which tab it belongs in)
    func fetch(_ id: Int) async -> Routine? { try? await api.detail(id: id).routine }

    /// The tab a routine is in, to show it from another screen (a click on a routine in Today)
    static func view(for r: Routine) -> String { r.active ? "today" : "archived" }

    func loadAllTags() async {
        if allTags.isEmpty { allTags = (try? await api.allTags()) ?? [] }
    }

    /// Creates a routine from the full set of fields ("Add routine"); returns it so the screen can select it
    @discardableResult
    func create(_ draft: RoutineDraft) async -> Routine? {
        guard draft.isComplete else { error = "Title is required."; return nil }
        do {
            let r = try await api.create(draft.body)
            error = nil
            return r
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Saves every field of the open routine. The row is updated in place; the list is loaded again when
    /// the change could move it (its schedule or time of day).
    @discardableResult
    func save(_ id: Int, _ draft: RoutineDraft) async -> Bool {
        guard draft.isComplete else { return false }
        do {
            let r = try await api.update(id: id, draft.body)
            if let i = routines.firstIndex(where: { $0.id == id }) { routines[i] = r.keeping(routines[i]) }
            if let o = open, o.routine.id == id { open = RoutineDetail(routine: r.keeping(o.routine), heatmap: o.heatmap, weeklyStats: o.weeklyStats) }
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    /// Marks the routine done for today, or undoes it. A routine that reaches its last day archives itself on
    /// the server, so the list is loaded again; the open routine's heatmap and bars are fetched again.
    func toggleToday(_ id: Int) async {
        do {
            let r = try await api.complete(id: id)
            error = nil
            await load()
            if selection == [id] { await refreshOpen(id) }
            _ = r
        } catch { self.error = error.localizedDescription }
    }

    func toggleArchived(_ id: Int) async {
        await change { try await self.api.archive(id: id) }
        dropFromSelection([id])
    }

    func delete(_ id: Int) async {
        await change { try await self.api.delete(id: id) }
        dropFromSelection([id])
    }

    // ── Several at once ─────────────────────────────────────────────────────

    /// Archive (Restore on the Archived tab) and Delete (the web's bulk bar)
    var bulkChoices: [(String, String)] {
        view == "archived" ? [("restore", "Restore"), ("delete", "Delete")] : [("archive", "Archive"), ("delete", "Delete")]
    }

    /// Applies `action` to the selected routines with one request. Returns how many the server changed.
    @discardableResult
    func applyBulk(_ action: String) async -> Int {
        let ids = Array(selection)
        guard !ids.isEmpty else { return 0 }
        do {
            let n = try await api.bulk(action: action, ids: ids)
            selection = []; open = nil
            await load()
            return n
        } catch { self.error = error.localizedDescription; return 0 }
    }

    // ── Internals ───────────────────────────────────────────────────────────

    private func refreshOpen(_ id: Int) async {
        if let d = try? await api.detail(id: id), selection == [id] { open = d }
    }

    private func change(_ call: () async throws -> Void) async {
        do { try await call(); error = nil; await load() }
        catch { self.error = error.localizedDescription }
    }

    private func dropFromSelection(_ ids: [Int]) {
        selection.subtract(ids)
        if let o = open, ids.contains(o.routine.id) { open = nil }
    }
}

private extension Routine {
    /// A save returns the routine without today's state or the counts; keep what the row already had
    func keeping(_ old: Routine) -> Routine {
        Routine(id: id, title: title, description: description, timeOfDay: timeOfDay, specificTime: specificTime,
                frequency: frequency, scheduleDays: scheduleDays, durationDays: durationDays, startDate: startDate,
                streakCurrent: streakCurrent, streakBest: streakBest, tags: tags, notify: notify, active: active,
                completionCount: old.completionCount, completedToday: old.completedToday, dueToday: old.dueToday,
                finishedChallenge: old.finishedChallenge, createdAt: createdAt ?? old.createdAt)
    }
}
