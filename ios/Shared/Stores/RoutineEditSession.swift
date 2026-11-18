import SwiftUI

/// Autosave for the routine in the Mac detail pane. The pane edits `draft`; about a second after the last
/// change (or when `flush()` is called, on leaving a field or picking another routine) the whole draft is
/// sent through `RoutinesStore.save`. A draft without a title is not sent, and goes back to what was saved
/// when the person leaves. No interface in here, so it is unit tested.
@MainActor @Observable
final class RoutineEditSession {
    enum SaveState: Equatable { case idle, saving, saved, failed }

    let routineId: Int
    private let store: RoutinesStore
    private let delay: Duration
    /// What the server has
    private(set) var saved: RoutineDraft
    private(set) var state: SaveState = .idle
    private var pending: Task<Void, Never>?

    var draft: RoutineDraft {
        didSet { if draft != oldValue { scheduleSave() } }
    }

    init(routine: Routine, store: RoutinesStore, delay: Duration = .seconds(1)) {
        routineId = routine.id
        self.store = store
        self.delay = delay
        let d = RoutineDraft(routine)
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
        if await store.save(routineId, sending) {
            saved = sending
            if isDirty { scheduleSave() } else { state = .saved }
        } else {
            state = .failed
        }
    }

    /// Takes a change made somewhere else as both the saved and the shown values (ignored while editing)
    func adopt(_ routine: Routine) {
        guard !isDirty else { return }
        let d = RoutineDraft(routine)
        saved = d
        draft = d
    }

    /// Puts one text field back to what was last saved (Escape in a field)
    func revert(_ field: WritableKeyPath<RoutineDraft, String>) {
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
