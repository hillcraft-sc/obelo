import SwiftUI

/// A row of pills in a rounded tray, one filled (web: notes/_type-selector.ejs). It wraps onto more lines
/// when there isn't room. Each pill is a button; the group reads as "label, option, selected" to VoiceOver.
struct KitPillSelector<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var label: String

    var body: some View {
        KitFlowLayout(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Pill(title: options[i].label, selected: options[i].value == selection) { selection = options[i].value }
            }
        }
        .padding(4)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private struct Pill: View {
        @Environment(\.theme) private var theme
        @State private var hovering = false
        let title: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? theme.onAccent : hovering ? theme.text200 : theme.textMuted)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(selected ? theme.accent : hovering ? theme.h1 : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }
    }
}
