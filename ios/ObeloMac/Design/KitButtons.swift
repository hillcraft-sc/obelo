import SwiftUI

// Buttons: primary, secondary, danger, ghost (the web's button classes), and the icon button.
// Use `.keyboardShortcut(.defaultAction)` / `.cancelAction` on the button for Return / Escape.

struct KitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, ghost }
    let kind: Kind
    var small = false
    /// Shows a spinner before the label and ignores clicks (a request is running)
    var busy = false
    /// Stretches to the width it is given (sign-in)
    var fullWidth = false

    init(_ kind: Kind, small: Bool = false, busy: Bool = false, fullWidth: Bool = false) {
        self.kind = kind
        self.small = small
        self.busy = busy
        self.fullWidth = fullWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        KitButtonBody(kind: kind, small: small, busy: busy, fullWidth: fullWidth, configuration: configuration)
    }
}

private struct KitButtonBody: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    let kind: KitButtonStyle.Kind
    let small: Bool
    let busy: Bool
    let fullWidth: Bool
    let configuration: ButtonStyleConfiguration

    private var pressed: Bool { configuration.isPressed }

    private var fill: Color {
        switch kind {
        case .primary: pressed ? theme.accentDark : hovering ? theme.accentHover : theme.accent
        case .secondary: pressed ? theme.h3 : hovering ? theme.h2 : theme.elevated
        case .danger: pressed ? theme.red800 : hovering ? theme.red500 : theme.red700
        case .ghost: hovering || pressed ? theme.elevated : .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: theme.onAccent
        case .secondary: theme.text200
        case .danger: theme.onStatusFill
        case .ghost: hovering ? theme.text300 : theme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(foreground) }
            configuration.label
        }
            .font(.system(size: small ? 12 : 14, weight: .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, small ? 10 : 14).padding(.vertical, small ? 4 : 6)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border2)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .allowsHitTesting(!busy)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A button that is only an icon. The label is required: it is the tooltip and the VoiceOver name.
struct KitIconButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    let systemImage: String
    let label: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? (destructive ? theme.red400 : theme.text300) : theme.textMuted)
                .frame(width: 26, height: 26)
                .background(hovering ? theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Accent-coloured text that acts like a link ("Have a setup code?", "Change", "Back to sign in")
struct KitLinkButton: View {
    enum Tone { case accent, muted }
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let title: String
    var size: CGFloat = 13
    /// `.muted` is the quiet grey the dashboard cards use for "All tasks →"
    var tone: Tone = .accent
    let action: () -> Void

    private var colour: Color {
        switch tone {
        case .accent: hovering ? theme.accentTextLight : theme.accentText
        case .muted: hovering ? theme.text400 : theme.textMuted
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: size)).foregroundStyle(colour)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A message above a form: red for a problem, green for a notice (web: the red and green boxes on the login page)
struct KitBanner: View {
    enum Kind { case error, notice, neutral, warn }
    @Environment(\.theme) private var theme
    let kind: Kind
    let text: String

    var body: some View {
        let fill: Color = switch kind { case .error: theme.red950; case .notice: theme.green950; case .neutral: theme.surface; case .warn: theme.amber950 }
        let edge: Color = switch kind { case .error: theme.red800; case .notice: theme.green800; case .neutral: theme.border1; case .warn: theme.amber900 }
        let ink: Color = switch kind { case .error: theme.red300; case .notice: theme.green300; case .neutral: theme.text400; case .warn: theme.amber300 }
        Text(text)
            .font(.system(size: 14)).foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(edge))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// A small count or label in a pill (web: the grey count beside a card title, the amber "N slipping")
struct KitBadge: View {
    enum Tone { case neutral, warn, info }
    @Environment(\.theme) private var theme
    let text: String
    var tone: Tone = .neutral
    /// A border and no fill, for the pill that acts as a button
    var outlined = false

    var body: some View {
        let ink: Color = switch tone { case .warn: theme.amber400; case .info: theme.blue400; case .neutral: theme.text400 }
        let fill: Color = switch tone { case .warn: theme.amber900.opacity(0.5); case .info: theme.blue500.opacity(0.2); case .neutral: theme.elevated }
        Text(text)
            .font(.system(size: outlined ? 12 : 10, weight: outlined ? .regular : .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, outlined ? 12 : 6).padding(.vertical, outlined ? 6 : 2)
            .background(outlined ? .clear : fill,
                        in: outlined ? AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) : AnyShape(Capsule()))
            .overlay {
                if outlined { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tone == .warn ? theme.amber900 : theme.border2) }
            }
    }
}

/// A button that opens a menu of actions (Snooze: 15 min, 1 hour, Tomorrow). The look of a small secondary
/// button with a chevron; the items are ordinary `Button`s.
struct KitActionMenu<Content: View>: View {
    let title: String
    var systemImage: String?
    var small = true
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).accessibilityHidden(true)
            }
        }
        .menuStyle(.button)
        .buttonStyle(KitButtonStyle(.secondary, small: small))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }
}
