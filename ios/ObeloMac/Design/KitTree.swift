import SwiftUI

/// One row of a folder tree (web: the workspace's tree): a folder with a collapse arrow, or a note, indented
/// by depth. Folders show their own buttons while the pointer is over the row (`trailing`); a row can be
/// highlighted as the place something is being dropped.
struct KitTreeRow<Trailing: View>: View {
    enum Kind { case folder(expanded: Bool, hasChildren: Bool), note }

    @Environment(\.theme) private var theme
    @State private var hovering = false
    let title: String
    let kind: Kind
    var depth = 0
    var selected = false
    var dropTargeted = false
    var pinned = false
    var locked = false
    var onToggle: (() -> Void)?
    var onClick: () -> Void = {}
    var onDoubleClick: (() -> Void)?
    @ViewBuilder var trailing: (_ hovering: Bool) -> Trailing

    private var isFolder: Bool { if case .folder = kind { true } else { false } }

    var body: some View {
        HStack(spacing: 4) {
            if case .folder(let expanded, let hasChildren) = kind {
                Button { onToggle?() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textMuted)
                        .frame(width: 16, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hasChildren ? 1 : 0.3)
                .help(expanded ? "Collapse" : "Expand")
                .accessibilityLabel(expanded ? "Collapse \(title)" : "Expand \(title)")
            } else {
                Spacer().frame(width: 16)
            }
            if pinned { Circle().fill(theme.amber400).frame(width: 6, height: 6).accessibilityLabel("Pinned") }
            Text(title)
                .font(.system(size: 13, weight: isFolder ? .medium : .regular))
                .foregroundStyle(selected ? theme.textPrimary : isFolder ? theme.text200 : hovering ? theme.text200 : theme.text300)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if locked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(theme.textMuted).accessibilityLabel("Locked") }
            trailing(hovering)
        }
        .padding(.leading, 6 + CGFloat(depth) * 14).padding(.trailing, 6).padding(.vertical, 3)
        .background(selected ? theme.accent.opacity(0.22) : dropTargeted ? theme.accent.opacity(0.3) : hovering ? theme.elevated.opacity(0.6) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { (onDoubleClick ?? onClick)() }
        .onTapGesture { onClick() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Open") { (onDoubleClick ?? onClick)() }
        .accessibilityAction(named: "Select") { onClick() }
    }
}

extension KitTreeRow where Trailing == EmptyView {
    init(title: String, kind: Kind, depth: Int = 0, selected: Bool = false, dropTargeted: Bool = false, pinned: Bool = false,
         locked: Bool = false, onToggle: (() -> Void)? = nil, onClick: @escaping () -> Void = {}, onDoubleClick: (() -> Void)? = nil) {
        self.init(title: title, kind: kind, depth: depth, selected: selected, dropTargeted: dropTargeted, pinned: pinned,
                  locked: locked, onToggle: onToggle, onClick: onClick, onDoubleClick: onDoubleClick) { _ in EmptyView() }
    }
}
