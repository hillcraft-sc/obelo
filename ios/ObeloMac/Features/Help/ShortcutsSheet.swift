import SwiftUI

/// Every shortcut, grouped (the `?` sheet and the gallery draw this)
struct ShortcutsList: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(MacShortcuts.groups) { g in
                VStack(alignment: .leading, spacing: 6) {
                    KitGroupLabel(text: g.title)
                    KitShortcutTable(rows: g.rows)
                }
            }
        }
    }
}

/// `?`: the keyboard shortcuts on their own, read only, from any screen
struct ShortcutsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(KitButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            KitDivider()
            ScrollView { ShortcutsList().padding(24) }
        }
        .frame(width: 680, height: 560)
        .background(theme.page)
    }
}
