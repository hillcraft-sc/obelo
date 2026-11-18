import SwiftUI

// Rows that can be dragged into a new order (web: Sortable with a drag handle, lists/show.ejs).

/// The grip on the left of a reorderable row. Drag it to move the row; the row is the drop target.
struct KitDragHandle: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let id: Int

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(hovering ? theme.text400 : theme.border2)
            .frame(width: 18, height: 24)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .draggable("obelo-row:\(id)")
            .help("Drag to reorder (⌥↑ ⌥↓ moves the selected row)")
            .accessibilityLabel("Reorder")
    }
}

extension View {
    /// Makes the view a place a `KitDragHandle` row can be dropped. `move(draggedID)` runs on a drop; the
    /// line above or below shows where it will land (`below` when the dragged row comes from above).
    func kitReorderTarget(isTargeted: Binding<Bool>, move: @escaping (_ draggedID: Int) -> Bool) -> some View {
        modifier(KitReorderTarget(isTargeted: isTargeted, move: move))
    }
}

private struct KitReorderTarget: ViewModifier {
    @Environment(\.theme) private var theme
    @Binding var isTargeted: Bool
    let move: (Int) -> Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Rectangle().fill(theme.accentHover).frame(height: 2).opacity(isTargeted ? 1 : 0)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let s = items.first, s.hasPrefix("obelo-row:"), let id = Int(s.dropFirst("obelo-row:".count)) else { return false }
                return move(id)
            } isTargeted: { isTargeted = $0 }
    }
}

/// A round badge with a person's first letter (web: the share list's avatar)
struct KitAvatar: View {
    @Environment(\.theme) private var theme
    let name: String

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(theme.accent, in: Circle())
            .accessibilityHidden(true)
    }
}
