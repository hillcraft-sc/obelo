import SwiftUI

// The search palette's pieces (web: partials/search-modal.ejs): the dimmed backdrop with a centred box, the
// borderless field with its "Esc" tag, a result row with the matching words highlighted, and the footer key caps.

/// A small key cap ("Esc", "↵", "↑↓")
struct KitKeyCap: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.textMuted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.border2))
            .accessibilityHidden(true)
    }
}

/// A box over a dimmed window, centred near the top: 576 points wide, never taller than 70% of the window.
/// A click on the backdrop calls `onClose`.
struct KitPalette<Content: View>: View {
    @Environment(\.theme) private var theme
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.6)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                VStack(spacing: 0) { content }
                    .frame(width: min(576, geo.size.width - 32))
                    .frame(maxHeight: geo.size.height * 0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.border2))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
                    .padding(.top, 64)
                    .accessibilityAddTraits(.isModal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The palette's field: icon, text, "Esc" tag. Up and down arrows, Return and Escape go to the closures,
/// so the keyboard works while the cursor stays in the field.
struct KitPaletteField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let placeholder: String
    @Binding var text: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onEscape: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(theme.textMuted).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 14)).foregroundStyle(theme.textPrimary)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(onSubmit)
                .onKeyPress(.upArrow) { onMove(-1); return .handled }
                .onKeyPress(.downArrow) { onMove(1); return .handled }
                .onKeyPress(.escape) { onEscape(); return .handled }
                .accessibilityLabel("Search")
            KitKeyCap(text: "Esc")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border1).frame(height: 1) }
        .onAppear { focused = true }
    }
}

/// A title with the words that matched drawn in the accent colour on a soft background (web: `<mark>`)
struct KitHighlightedText: View {
    @Environment(\.theme) private var theme
    let pieces: [HighlightPiece]
    var color: Color?

    var body: some View {
        Text(attributed).lineLimit(1)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for p in pieces {
            var a = AttributedString(p.text)
            a.foregroundColor = p.isMatch ? theme.accentTextLight : (color ?? theme.text100)
            if p.isMatch { a.backgroundColor = theme.accent.opacity(0.3) }
            out += a
        }
        return out
    }
}

/// One search result: the kind's icon, the title with the matching words marked, a grey line under it
struct KitSearchRow: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: [HighlightPiece]
    let subtitle: String?
    var isHighlighted: Bool
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(theme.textMuted).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    KitHighlightedText(pieces: title).font(.system(size: 14, weight: .medium))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .background(isHighlighted ? theme.elevated : hovering ? theme.elevated.opacity(0.5) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.map(\.text).joined() + (subtitle.map { ", \($0)" } ?? ""))
    }
}
