import SwiftUI

/// Autosave for the reminder in the Mac detail pane. The pane edits `draft`; about a second after the last
/// change (or when `flush()` is called, on leaving a field or picking another reminder) the whole draft is
/// sent through `RemindersStore.save`. A draft without a title, date or time is not sent, and goes back to
/// what was saved when the person leaves. No interface in here, so it is unit tested.
@MainActor @Observable
final class ReminderEditSession {
    enum SaveState: Equatable { case idle, saving, saved, failed }

    let reminderId: Int
    private let store: RemindersStore
    private let delay: Duration
    /// What the server has
    private(set) var saved: ReminderDraft
    private(set) var state: SaveState = .idle
    private var pending: Task<Void, Never>?

    var draft: ReminderDraft {
        didSet { if draft != oldValue { scheduleSave() } }
    }

    init(reminder: ReminderItem, store: RemindersStore, delay: Duration = .seconds(1)) {
        reminderId = reminder.id
        self.store = store
        self.delay = delay
        let d = ReminderDraft(reminder)
        saved = d
        draft = d
    }

    var isDirty: Bool { draft != saved }

    func flush(leaving: Bool = false) async {
        pending?.cancel()
        pending = nil
        if leaving, !draft.isComplete { draft = saved }
        guard isDirty, draft.isComplete else { return }
        let sending = draft
        state = .saving
        if await store.save(reminderId, sending) {
            saved = sending
            if isDirty { scheduleSave() } else { state = .saved }
        } else {
            state = .failed
        }
    }

    /// Takes a change made somewhere else as both the saved and the shown values (ignored while editing)
    func adopt(_ reminder: ReminderItem) {
        guard !isDirty else { return }
        let d = ReminderDraft(reminder)
        saved = d
        draft = d
    }

    /// Puts one text field back to what was last saved (Escape in a field)
    func revert(_ field: WritableKeyPath<ReminderDraft, String>) {
        draft[keyPath: field] = saved[keyPath: field]
    }

    private func scheduleSave() {
        pending?.cancel()
        state = .idle
        let wait = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }
}
