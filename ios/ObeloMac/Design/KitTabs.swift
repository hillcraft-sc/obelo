import SwiftUI

/// One tab. A badge shows a count; `warn` makes it red (web: Slipping).
struct KitTab: Identifiable, Equatable {
    let id: String
    let label: String
    var badge: Int?
    var warn = false
}

/// Underlined section tabs with count badges (web: partials/tabs.ejs)
struct KitTabs: View {
    @Environment(\.theme) private var theme
    let tabs: [KitTab]
    @Binding var selection: String

    var body: some View {
        // Scrolls sideways when the pane is too narrow for every tab (web: overflow-x-auto)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    KitTabButton(tab: tab, active: tab.id == selection) { selection = tab.id }
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border1).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

private struct KitTabButton: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let tab: KitTab
    let active: Bool
    let action: () -> Void

    private var badgeFill: Color { tab.warn ? theme.red500 : active ? theme.accentHover : theme.h2 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(tab.label).font(.system(size: 14)).lineLimit(1).fixedSize()
                if let badge = tab.badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(tab.warn ? theme.onStatusFill : theme.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(badgeFill, in: Capsule())
                }
            }
            .foregroundStyle(active ? theme.textPrimary : hovering ? theme.text300 : theme.textMuted)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(active ? theme.elevated : hovering ? theme.elevated.opacity(0.5) : .clear,
                        in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            .overlay(alignment: .bottom) {
                if active { Rectangle().fill(theme.accentHover).frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.badge.map { "\(tab.label), \($0)" } ?? tab.label)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}
