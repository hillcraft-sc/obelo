import SwiftUI

// Tags: the small `#tag` on a row, the filter pills above a list, and the tag picker (web:
// notes/_tag-picker.ejs and public/js/tag-picker.js): chosen tags as pills in a box, a drop-down
// of the user's other tags filtered by what's typed, and "Create #…" for a new one.

enum KitTag {
    /// The same clean-up the web picker does: trim, lower-case, drop leading #
    static func normalize(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while t.hasPrefix("#") { t.removeFirst() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The quiet `#tag` shown on a row
struct KitTagLabel: View {
    @Environment(\.theme) private var theme
    let tag: String

    var body: some View {
        Text("#\(tag)")
            .font(.system(size: 10)).foregroundStyle(theme.textMuted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel("Tag \(tag)")
    }
}

/// A `#tag` pill above a list: click to filter, click again to clear
struct KitTagFilterPill: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let tag: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? theme.onAccent : hovering ? theme.text300 : theme.textMuted)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(active ? theme.accent : theme.elevated, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(active ? "Clear the \(tag) filter" : "Show only #\(tag)")
        .accessibilityLabel("Tag \(tag)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A chosen tag inside the picker, with a remove button
struct KitTagChip: View {
    @Environment(\.theme) private var theme
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)").font(.system(size: 12))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Remove #\(tag)")
            .accessibilityLabel("Remove tag \(tag)")
        }
        .foregroundStyle(theme.accentTextLight)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(theme.accent.opacity(0.2), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.accentHover.opacity(0.3)))
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full
struct KitFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// The tag picker. `suggestions` is every tag the user already has.
struct KitTagPicker: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var highlight = 0
    @State private var overDropdown = false
    @Binding var tags: [String]
    let suggestions: [String]

    private var normalizedQuery: String { KitTag.normalize(query) }

    /// Existing tags not yet chosen, filtered by what's typed
    private var matches: [String] {
        suggestions.filter { !tags.contains($0) && (normalizedQuery.isEmpty || $0.contains(normalizedQuery)) }
    }

    private var canCreate: Bool {
        !normalizedQuery.isEmpty && !tags.contains(normalizedQuery) && !suggestions.contains(normalizedQuery)
    }

    private var rows: [(tag: String, isNew: Bool)] {
        matches.map { ($0, false) } + (canCreate ? [(normalizedQuery, true)] : [])
    }

    private var showsDropdown: Bool { (focused || overDropdown) && !rows.isEmpty }

    var body: some View {
        KitFlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                KitTagChip(tag: tag) { tags.removeAll { $0 == tag } }
            }
            TextField("", text: $query, prompt: Text(tags.isEmpty ? "Add a tag…" : "").foregroundStyle(theme.placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(theme.text100)
                .frame(minWidth: 128)
                .focused($focused)
                .onSubmit { commit() }
                .onKeyPress(.downArrow) { highlight = min(highlight + 1, max(rows.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { highlight = max(highlight - 1, 0); return .handled }
                .onKeyPress(.delete) {
                    guard query.isEmpty, !tags.isEmpty else { return .ignored }
                    tags.removeLast()
                    return .handled
                }
                .onChange(of: query) { _, _ in highlight = 0 }
                .accessibilityLabel("Add a tag")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitFieldChrome(focused: focused, hPadding: 10, vPadding: 6)
        .overlay(alignment: .bottomLeading) {
            if showsDropdown {
                dropdown.alignmentGuide(.bottom) { $0[.top] - 4 }
            }
        }
        .zIndex(1)
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { i, row in
                KitTagOption(tag: row.tag, isNew: row.isNew, highlighted: i == highlight) { add(row.tag) }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 280, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border2))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onHover { overDropdown = $0 }
    }

    private func commit() {
        if rows.indices.contains(highlight), !normalizedQuery.isEmpty || highlight > 0 {
            add(rows[highlight].tag)
        } else if !normalizedQuery.isEmpty {
            add(normalizedQuery)
        }
    }

    private func add(_ tag: String) {
        let t = KitTag.normalize(tag)
        if !t.isEmpty, !tags.contains(t) { tags.append(t) }
        query = ""
        highlight = 0
        focused = true
    }
}

private struct KitTagOption: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let tag: String
    let isNew: Bool
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isNew ? "Create #\(tag)" : "#\(tag)")
                .font(.system(size: 14))
                .foregroundStyle(isNew ? theme.accentText : theme.text200)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(highlighted || hovering ? theme.elevated : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
