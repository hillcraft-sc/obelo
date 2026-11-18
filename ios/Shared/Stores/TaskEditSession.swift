import SwiftUI

/// Autosave for the task in the Mac detail pane. The pane edits `draft`; about a second after the last
/// change (or when `flush()` is called, on leaving the field or picking another task) the whole draft is
/// sent through `TasksStore.save`. No interface in here, so it is unit tested.
@MainActor @Observable
final class TaskEditSession {
    enum SaveState: Equatable { case idle, saving, saved, failed }

    let taskId: Int
    private let store: TasksStore
    private let delay: Duration
    /// What the server has
    private(set) var saved: TaskDraft
    private(set) var state: SaveState = .idle
    private var pending: Task<Void, Never>?

    var draft: TaskDraft {
        didSet { if draft != oldValue { scheduleSave() } }
    }

    init(task: TaskItem, store: TasksStore, delay: Duration = .seconds(1)) {
        taskId = task.id
        self.store = store
        self.delay = delay
        let d = TaskDraft(task)
        saved = d
        draft = d
    }

    var isDirty: Bool { draft != saved }
    private var titleIsEmpty: Bool { draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Saves now if anything changed. `leaving` is true when the person is moving away: an empty title
    /// (the server needs one) goes back to the saved title instead of being kept.
    func flush(leaving: Bool = false) async {
        pending?.cancel()
        pending = nil
        if leaving, titleIsEmpty { draft.title = saved.title }
        guard isDirty, !titleIsEmpty else { return }
        let sending = draft
        state = .saving
        if await store.save(taskId, sending) {
            saved = sending
            if isDirty { scheduleSave() } else { state = .saved }
        } else {
            state = .failed
        }
    }

    /// Takes a change made somewhere else (the status menu on the task's row) as both the saved and the shown values.
    /// Ignored while there are unsaved edits, which the next save sends whole.
    func adopt(_ task: TaskItem) {
        guard !isDirty else { return }
        let d = TaskDraft(task)
        saved = d
        draft = d
    }

    /// Puts one field back to what was last saved (Escape in a field)
    func revert(_ field: WritableKeyPath<TaskDraft, String>) {
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
