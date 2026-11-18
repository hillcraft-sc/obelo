import AppKit
import SwiftUI

// List rows and what goes in them: the row itself (hover, selection, ⌘/⇧-click), the complete
// circle, the priority icon, and the bulk action bar. Web: tasks/_row.ejs and the bulk bar in
// tasks/index.ejs.

/// A row in a list. Click, ⌘-click and ⇧-click are reported with their modifiers so the screen can
/// feed them to `RowSelection`. Attach `.contextMenu` to the row for the right-click menu.
struct KitRow<Content: View>: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    var isSelected = false
    var onClick: (_ command: Bool, _ shift: Bool) -> Void = { _, _ in }
    /// The closure gets whether the pointer is over the row, for controls that show on hover
    @ViewBuilder var content: (_ hovering: Bool) -> Content

    var body: some View {
        content(hovering)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accentSurface : hovering ? theme.elevated.opacity(0.5) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                let flags = NSEvent.modifierFlags
                onClick(flags.contains(.command), flags.contains(.shift))
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Select") { onClick(false, false) }
    }
}

/// The round "complete" button (web: the w-5 h-5 circle). Done rows show a tick and restore on click.
struct KitCompleteCircle: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let done: Bool
    /// The ring colour while open and not hovered (the dashboard uses accent for focus, red for overdue)
    var tint: Color?
    let action: () -> Void

    private var ring: Color {
        done ? (hovering ? theme.red500 : theme.green500) : (hovering ? theme.green500 : (tint ?? theme.border3))
    }
    private var fill: Color {
        done ? (hovering ? theme.red500 : theme.green500).opacity(0.2) : (hovering ? theme.green500.opacity(0.2) : .clear)
    }

    var body: some View {
        Button(action: action) {
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(ring, lineWidth: 2))
                .overlay {
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(hovering ? theme.red400 : theme.green400)
                    }
                }
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(done ? "Restore to inbox" : "Mark complete")
        .accessibilityLabel(done ? "Restore to inbox" : "Mark complete")
    }
}

/// One, two or three chevrons for low, medium and high; nothing (same width) for none
struct KitPriorityIcon: View {
    @Environment(\.theme) private var theme
    let priority: String

    private var count: Int {
        switch priority { case "low": 1; case "medium": 2; case "high": 3; default: 0 }
    }

    var body: some View {
        Chevrons(count: count)
            .stroke(theme.text400, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 14, height: 14)
            .help(count == 0 ? "" : "Priority: \(priority.capitalized)")
            .accessibilityLabel(count == 0 ? "No priority" : "Priority: \(priority.capitalized)")
    }

    private nonisolated struct Chevrons: Shape {
        let count: Int
        func path(in rect: CGRect) -> Path {
            var p = Path()
            guard count > 0 else { return p }
            // Chevrons drawn in the web icon's 15 x 7.5 box, 6 apart, centred vertically
            let scale = rect.width / 15
            let total = (7.5 + 6 * CGFloat(count - 1)) * scale
            let top = rect.midY - total / 2
            for i in 0..<count {
                let y = top + CGFloat(i) * 6 * scale
                p.move(to: CGPoint(x: rect.minX, y: y + 7.5 * scale))
                p.addLine(to: CGPoint(x: rect.midX, y: y))
                p.addLine(to: CGPoint(x: rect.maxX, y: y + 7.5 * scale))
            }
            return p
        }
    }
}

/// The bar that appears over a list when several rows are selected
struct KitBulkBar: View {
    @Environment(\.theme) private var theme
    let count: Int
    let actions: [(value: String, label: String)]
    @Binding var action: String
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accentTextLight)
                .frame(maxWidth: .infinity, alignment: .leading)
            KitSelect(options: actions, selection: $action, label: "Bulk action")
                .frame(width: 180)
            Button("Apply", action: onApply).buttonStyle(KitButtonStyle(.primary, small: true))
            Button("Cancel", action: onCancel).buttonStyle(KitButtonStyle(.ghost, small: true))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.accentSurface.opacity(0.5))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.accentBorder9).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

/// The bulk bar for a list that can only delete (web: bookmarks): "N selected", "Delete selected", "Cancel"
struct KitBulkDeleteBar: View {
    @Environment(\.theme) private var theme
    let count: Int
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accentTextLight)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Delete selected", action: onDelete).buttonStyle(KitButtonStyle(.danger, small: true))
            Button("Cancel", action: onCancel).buttonStyle(KitButtonStyle(.ghost, small: true))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.accentSurface.opacity(0.5))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.accentBorder9).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

/// The small coloured dot for priority (web: the dashboard rows); none is grey
struct KitPriorityDot: View {
    @Environment(\.theme) private var theme
    let priority: String
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(theme.priorityDot(priority)).frame(width: size, height: size)
            .help(priority == "none" ? "" : "Priority: \(priority.capitalized)")
            .accessibilityLabel(priority == "none" ? "No priority" : "Priority: \(priority.capitalized)")
    }
}

/// The rounded-square tick box routines use: green check when done, dashed and inert when not scheduled today
struct KitCompleteSquare: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let done: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: action) {
            shape.fill(done ? (hovering ? .clear : theme.green500.opacity(0.2)) : (hovering ? theme.green500.opacity(0.1) : .clear))
                .overlay {
                    if enabled {
                        shape.strokeBorder(done ? (hovering ? theme.red400 : theme.green500) : (hovering ? theme.green500 : theme.border3), lineWidth: 2)
                    } else {
                        shape.strokeBorder(theme.border2, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    }
                }
                .overlay {
                    if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.green400) }
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(!enabled ? "Not scheduled today" : done ? "Mark incomplete" : "Mark complete")
        .accessibilityLabel(!enabled ? "Not scheduled today" : done ? "Mark incomplete" : "Mark complete")
    }
}
