import SwiftUI

// The Today page's logic, with no interface: the dashboard data, which cards are on and in what order,
// and the quick actions (complete a task or reminder, snooze, tick a routine, mark a note reviewed).
// Each action takes the row off at once and puts the data back if the server refuses. The Mac screen
// is built on it. It talks to the server through `TodayAPI`, so tests can use a stub.

@MainActor
protocol TodayAPI {
    func dashboard() async throws -> Dashboard
    func completeTask(id: Int) async throws
    func completeReminder(id: Int) async throws
    func snoozeReminder(id: Int, duration: String) async throws
    func toggleRoutine(id: Int) async throws -> Routine
    func markReviewed(noteId: Int) async throws
}

@MainActor
struct LiveTodayAPI: TodayAPI {
    private var api: APIClient { .shared }
    private struct RoutineResponse: Decodable { let routine: Routine }

    func dashboard() async throws -> Dashboard { try await api.get("/dashboard") }
    func completeTask(id: Int) async throws { try await api.post("/tasks/\(id)/complete") }
    func completeReminder(id: Int) async throws { try await api.post("/reminders/\(id)/complete") }
    func snoozeReminder(id: Int, duration: String) async throws { try await api.post("/reminders/\(id)/snooze", ["duration": duration]) }
    func toggleRoutine(id: Int) async throws -> Routine { (try await api.post("/routines/\(id)/complete") as RoutineResponse).routine }
    func markReviewed(noteId: Int) async throws { try await api.post("/notes/\(noteId)/flag") }
}

@MainActor @Observable
final class TodayStore {
    private let api: TodayAPI

    private(set) var data: Dashboard?
    private(set) var loaded = false
    var error: String?
    /// A short confirmation for a toast ("Snoozed 1 hour"); the screen shows it and clears it
    var notice: String?

    init(api: TodayAPI) { self.api = api }
    convenience init() { self.init(api: LiveTodayAPI()) }

    // ── What to show ────────────────────────────────────────────────────────

    /// The cards the person switched on, in their order (Settings ▸ Dashboard). Quick Capture is not
    /// one of them: it is always last.
    var cards: [String] { data?.widgets.filter(\.enabled).map(\.key) ?? [] }

    var focusTasks: [TaskItem] { data?.focusTasks ?? [] }
    var events: [CalendarEvent] { data?.events ?? [] }
    var due: [Dashboard.DueEntry] { data?.due ?? [] }
    var routines: [Routine] { data?.routines ?? [] }
    var slippingCount: Int { data?.slippingCount ?? 0 }
    var resurfaced: Dashboard.Resurfaced? { data?.resurfaced }
    var review: [Dashboard.ReviewNote] { data?.review ?? [] }
    var stale: [Dashboard.StaleNote] { data?.stale ?? [] }

    var routinesDone: Int { routines.filter(\.completedToday).count }
    var needsReviewCount: Int { review.count + stale.count }

    /// Routines by time of day, in the order morning, afternoon, evening, anytime. A routine with an
    /// unknown time of day goes under anytime.
    var routineGroups: [(timeOfDay: String, label: String, routines: [Routine])] {
        let known = Fmt.timeOfDay
        return known.compactMap { tod in
            let rows = routines.filter { $0.timeOfDay == tod || (tod == "anytime" && !known.contains($0.timeOfDay)) }
            return rows.isEmpty ? nil : (tod, Fmt.timeLabels[tod] ?? tod, rows)
        }
    }

    /// The "Anytime" heading only shows when another group does too
    var showsAnytimeHeading: Bool { routineGroups.contains { $0.timeOfDay != "anytime" } }

    // ── Loading ─────────────────────────────────────────────────────────────

    func load() async {
        do {
            data = try await api.dashboard()
            loaded = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    // ── Quick actions ───────────────────────────────────────────────────────

    func complete(task: TaskItem) async {
        await act(reloadAfter: task.recurring) {
            self.data?.focusTasks.removeAll { $0.id == task.id }
            self.data?.due.removeAll { $0.task?.id == task.id }
        } call: { try await self.api.completeTask(id: task.id) }
    }

    func complete(reminder: ReminderItem) async {
        await act(reloadAfter: reminder.recurring) {
            self.data?.due.removeAll { $0.reminder?.id == reminder.id }
        } call: { try await self.api.completeReminder(id: reminder.id) }
    }

    /// `duration` is "1hour" or "tomorrow", as the server expects
    func snooze(_ reminder: ReminderItem, _ duration: String) async {
        let ok = await act(reloadAfter: false) {
            self.data?.due.removeAll { $0.reminder?.id == reminder.id }
        } call: { try await self.api.snoozeReminder(id: reminder.id, duration: duration) }
        if ok { notice = duration == "tomorrow" ? "Snoozed until tomorrow" : "Snoozed 1 hour" }
    }

    /// Ticks or unticks a routine for today. The server's answer replaces the row (streak, progress).
    func toggle(routine: Routine) async {
        guard let i = data?.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        let before = data
        data?.routines[i].completedToday.toggle()
        do {
            let updated = try await api.toggleRoutine(id: routine.id)
            if let j = data?.routines.firstIndex(where: { $0.id == routine.id }) { data?.routines[j] = updated }
            error = nil
        } catch {
            data = before
            self.error = error.localizedDescription
        }
    }

    func markReviewed(_ note: Dashboard.ReviewNote) async {
        await act(reloadAfter: false) {
            self.data?.review.removeAll { $0.id == note.id }
        } call: { try await self.api.markReviewed(noteId: note.id) }
    }

    // ── Internals ───────────────────────────────────────────────────────────

    /// Changes the data at once, calls the server, and puts the data back if the call fails.
    /// A repeating item comes back with its next date, so the page is reloaded after it.
    @discardableResult
    private func act(reloadAfter: Bool, _ change: () -> Void, call: () async throws -> Void) async -> Bool {
        let before = data
        change()
        do {
            try await call()
            error = nil
            if reloadAfter { await load() }
            return true
        } catch {
            data = before
            self.error = error.localizedDescription
            return false
        }
    }
}
