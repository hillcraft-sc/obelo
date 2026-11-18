import SwiftUI

// A table: column headings you can click to sort, and the widths the rows share with them. Used by
// Bookmarks (web: the card list in bookmarks/index.ejs becomes a table on the Mac, as the Mac plan says).

/// One column. A nil width takes whatever room is left.
struct KitTableColumn: Identifiable, Equatable {
    let id: String
    let label: String
    var width: CGFloat?
    var sortable = true
}

extension View {
    /// Gives a cell its column's width, so rows line up under the headings
    func kitTableCell(_ column: KitTableColumn) -> some View {
        frame(minWidth: column.width == nil ? 120 : nil, maxWidth: column.width ?? .infinity, alignment: .leading)
            .frame(width: column.width, alignment: .leading)
    }
}

/// The heading row. Click a heading to sort by it; click it again to reverse. The sorted one shows an arrow.
struct KitTableHeader: View {
    @Environment(\.theme) private var theme
    let columns: [KitTableColumn]
    let sortedBy: String
    let ascending: Bool
    let onSort: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(columns) { column in
                KitTableHeading(column: column, active: column.id == sortedBy, ascending: ascending) { onSort(column.id) }
                    .kitTableCell(column)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(theme.elevated.opacity(0.5))
        .overlay(alignment: .bottom) { KitDivider() }
        .accessibilityElement(children: .contain)
    }
}

private struct KitTableHeading: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let column: KitTableColumn
    let active: Bool
    let ascending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(column.label.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                if active {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(active ? theme.text300 : hovering && column.sortable ? theme.text400 : theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!column.sortable)
        .onHover { hovering = $0 }
        .help(column.sortable ? "Sort by \(column.label.lowercased())" : column.label)
        .accessibilityLabel(column.label)
        .accessibilityHint(column.sortable ? "Sorts the table" : "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A site's small icon (web: the DuckDuckGo icon next to each bookmark), a plain globe while it loads or when
/// the site has none
struct KitSiteIcon: View {
    @Environment(\.theme) private var theme
    let host: String
    var size: CGFloat = 16

    var body: some View {
        AsyncImage(url: URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")) { image in
            image.resizable().scaledToFit().opacity(0.85)
        } placeholder: {
            Image(systemName: "globe").font(.system(size: size - 3)).foregroundStyle(theme.textMuted)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }
}
