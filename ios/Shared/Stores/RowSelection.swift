import Foundation

/// Which rows are selected in a list, with the Mac's rules: a plain click selects one row, ⌘-click
/// adds or removes one, ⇧-click selects the run from the anchor row, and ⌘⇧-click adds that run.
/// The anchor is the row last clicked without ⇧. No interface in here, so it is unit tested.
struct RowSelection<ID: Hashable>: Equatable {
    private(set) var selected: Set<ID> = []
    private(set) var anchor: ID?

    var isEmpty: Bool { selected.isEmpty }
    var count: Int { selected.count }
    /// The one selected row, or nil when none or several are selected
    var single: ID? { selected.count == 1 ? selected.first : nil }

    func contains(_ id: ID) -> Bool { selected.contains(id) }

    /// Applies a click on `id`. `ordered` is the rows as shown, top to bottom.
    mutating func click(_ id: ID, in ordered: [ID], command: Bool = false, shift: Bool = false) {
        if shift, let anchor, let a = ordered.firstIndex(of: anchor), let b = ordered.firstIndex(of: id) {
            let run = Set(ordered[min(a, b)...max(a, b)])
            selected = command ? selected.union(run) : run
        } else if command {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        } else {
            selected = [id]
            anchor = id
        }
    }

    /// Arrow keys: selects the row `delta` places from the current one (the first row when nothing is
    /// selected), staying inside the list.
    mutating func step(_ delta: Int, in ordered: [ID]) {
        guard !ordered.isEmpty else { return }
        let current = anchor.flatMap { ordered.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ordered.count - 1) } ?? (delta >= 0 ? 0 : ordered.count - 1)
        selected = [ordered[next]]
        anchor = ordered[next]
    }

    mutating func selectAll(in ordered: [ID]) {
        selected = Set(ordered)
        anchor = ordered.first
    }

    /// Makes the selection exactly `ids` (when the store changed it, e.g. after a delete). Keeps the anchor if it is still selected.
    mutating func set(_ ids: Set<ID>) {
        guard ids != selected else { return }
        selected = ids
        if let a = anchor, ids.contains(a) { return }
        anchor = ids.first
    }

    mutating func clear() {
        selected = []
        anchor = nil
    }

    /// Drops rows that are no longer in the list (after a filter, a delete or a reload)
    mutating func prune(to ordered: [ID]) {
        let present = Set(ordered)
        selected.formIntersection(present)
        if let a = anchor, !present.contains(a) { anchor = selected.first }
    }
}
