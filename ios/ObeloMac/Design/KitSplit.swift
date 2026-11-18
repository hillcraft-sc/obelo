import AppKit
import SwiftUI

/// Two panes side by side with a draggable divider. One pane has a width of its own, remembered under
/// `storageKey` (`fixed` says which); the other takes what is left and never gets narrower than its minimum.
struct KitSplitView<Leading: View, Trailing: View>: View {
    enum Fixed { case leading, trailing }

    @Environment(\.theme) private var theme
    let storageKey: String
    var fixed: Fixed = .leading
    var defaultWidth: CGFloat = 520
    var minLeading: CGFloat = 320
    var minTrailing: CGFloat = 320
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var width: CGFloat?
    @State private var dragStart: CGFloat?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            // The fixed pane's room: at least its own minimum, at most what leaves the other pane its minimum
            let lowest = fixed == .leading ? minLeading : minTrailing
            let other = fixed == .leading ? minTrailing : minLeading
            let highest = max(lowest, geo.size.width - other - 1)
            let w = min(max(width ?? stored, lowest), highest)
            HStack(spacing: 0) {
                if fixed == .leading {
                    leading.frame(width: w)
                    handle(current: w, lowest: lowest, highest: highest)
                    trailing.frame(maxWidth: .infinity)
                } else {
                    leading.frame(maxWidth: .infinity)
                    handle(current: w, lowest: lowest, highest: highest)
                    trailing.frame(width: w)
                }
            }
        }
    }

    private var key: String { "kitSplit.\(storageKey)" }
    private var stored: CGFloat {
        let saved = UserDefaults.standard.double(forKey: key)
        return saved > 0 ? CGFloat(saved) : defaultWidth
    }

    private func handle(current: CGFloat, lowest: CGFloat, highest: CGFloat) -> some View {
        divider
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? current
                    dragStart = start
                    let moved = fixed == .leading ? drag.translation.width : -drag.translation.width
                    width = min(max(start + moved, lowest), highest)
                }
                .onEnded { _ in
                    dragStart = nil
                    if let width { UserDefaults.standard.set(Double(width), forKey: key) }
                })
    }

    /// A quiet hairline with a wider strip to grab. The line is drawn up to the top of the window, like the
    /// dividers between the panes in Notes, but only the part below the title bar can be grabbed: the title
    /// bar takes any click above that to move the window. The line is a little stronger while pointed at or dragged.
    private var divider: some View {
        Color.clear
            .frame(width: 9)
            .contentShape(Rectangle())
            .background {
                Rectangle().fill(hovering || dragStart != nil ? theme.border3 : theme.border1)
                    .frame(width: 1)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .help("Drag to resize")
            .accessibilityLabel("Resize panes")
            .accessibilityAddTraits(.isButton)
    }
}
