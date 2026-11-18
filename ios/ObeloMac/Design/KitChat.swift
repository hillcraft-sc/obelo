import AppKit
import SwiftUI

// AI Chat's pieces (web: ai/index.ejs): the message bubbles, the typing dots, and the message box
// (Return sends, ⇧Return starts a new line, ⌘Return sends too).

/// One message. Yours sit on the right in the accent colour; the AI's on the left in a grey bubble, with the
/// "N messages remaining today" line under it. Text can be selected; hover for a Copy button.
struct KitChatBubble: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let text: String
    let isUser: Bool
    var remaining: String?
    var onCopy: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 56) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 14)).lineSpacing(3)
                    .foregroundStyle(isUser ? theme.onAccent : theme.text100)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(isUser ? theme.accent : theme.elevated, in: shape)
                    .overlay { if !isUser { shape.strokeBorder(theme.border2) } }
                if let remaining {
                    Text(remaining).font(.system(size: 10)).foregroundStyle(theme.textMuted)
                }
            }
            .overlay(alignment: isUser ? .topLeading : .topTrailing) {
                if hovering {
                    KitIconButton(systemImage: "doc.on.doc", label: "Copy", action: onCopy)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .offset(x: isUser ? -30 : 30, y: 0)
                }
            }
            if !isUser { Spacer(minLength: 56) }
        }
        .onHover { hovering = $0 }
        .contextMenu { Button("Copy", action: onCopy) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isUser ? "You said: " : "Obelo said: ") + text)
    }

    private var shape: UnevenRoundedRectangle {
        isUser
            ? UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 4, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
    }
}

/// The three bouncing dots while a reply is on its way
struct KitTypingDots: View {
    @Environment(\.theme) private var theme
    @State private var up = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(theme.textMuted).frame(width: 8, height: 8)
                        .offset(y: up ? -4 : 0)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: up)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(theme.elevated, in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous).strokeBorder(theme.border2))
            Spacer(minLength: 0)
        }
        .onAppear { up = true }
        .accessibilityLabel("Thinking")
    }
}

/// The message box and its round Send button. Grows to five lines, then scrolls.
struct KitChatInput: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let placeholder: String
    @Binding var text: String
    @Binding var focusRequest: Bool
    var canSend: Bool
    var onSend: () -> Void
    @State private var height: CGFloat = 20
    @State private var focused = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ChatTextView(text: $text, height: $height, focusRequest: $focusRequest, focused: $focused,
                         isEnabled: isEnabled, textColor: NSColor(theme.textPrimary), caret: NSColor(theme.accentHover),
                         dark: theme.isDark, onSend: onSend)
                .frame(height: height)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder).font(.system(size: 14)).foregroundStyle(theme.placeholder)
                            .padding(.leading, 5).padding(.top, 2).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? theme.accentHover : theme.border2))
                .accessibilityLabel(placeholder)
            Button(action: onSend) {
                Image(systemName: "paperplane.fill").font(.system(size: 15)).foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
            .help("Send (Return)")
            .accessibilityLabel("Send")
        }
    }
}

/// A text view where Return sends, ⇧Return starts a new line, and ⌘Return sends
private final class SendingTextView: NSTextView {
    var onSend: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocus(false) }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !hasMarkedText() {
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSend()
            }
            return
        }
        super.keyDown(with: event)
    }
}

private struct ChatTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var focusRequest: Bool
    @Binding var focused: Bool
    let isEnabled: Bool
    let textColor: NSColor
    let caret: NSColor
    let dark: Bool
    let onSend: () -> Void

    private static let lineHeight: CGFloat = 20
    private static let maxHeight: CGFloat = 20 * 5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = SendingTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding = 5
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        scroll.documentView = tv
        context.coordinator.textView = tv
        style(tv)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? SendingTextView else { return }
        context.coordinator.parent = self
        tv.onSend = onSend
        tv.onFocus = { focus in DispatchQueue.main.async { focused = focus } }
        tv.isEditable = isEnabled
        tv.isSelectable = isEnabled
        style(tv)
        if tv.string != text {
            context.coordinator.updating = true
            tv.string = text
            context.coordinator.updating = false
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        context.coordinator.updateHeight()
        if focusRequest {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                focusRequest = false
            }
        }
    }

    private func style(_ tv: NSTextView) {
        let font = NSFont.systemFont(ofSize: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        tv.font = font
        tv.textColor = textColor
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
        tv.insertionPointColor = caret
        tv.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextView
        weak var textView: NSTextView?
        var updating = false

        init(_ parent: ChatTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !updating, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            updateHeight()
        }

        func updateHeight() {
            guard let tv = textView, let layout = tv.layoutManager, let container = tv.textContainer else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).height
            let h = min(max(used, ChatTextView.lineHeight), ChatTextView.maxHeight)
            if abs(h - parent.height) > 0.5 {
                DispatchQueue.main.async { self.parent.height = h }
            }
        }
    }
}
