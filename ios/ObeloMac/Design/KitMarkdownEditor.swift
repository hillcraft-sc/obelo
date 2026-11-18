import AppKit
import SwiftUI

/// Lets the toolbar and the Format menu act on the editor: apply a format to the selection, move the cursor in
@MainActor @Observable
final class KitMarkdownEditorController {
    fileprivate weak var textView: NSTextView?

    /// Applies a Markdown format (bold, a list, a link …) to the selection with the shared `MarkdownFormat`
    /// rules, as one undoable change, and selects what the web selects afterwards
    func apply(_ format: MarkdownFormat) {
        guard let tv = textView else { return }
        let text = tv.string
        let current = tv.selectedRange()
        guard let range = Range(current, in: text) else { return }
        let lo = text.distance(from: text.startIndex, to: range.lowerBound)
        let hi = text.distance(from: text.startIndex, to: range.upperBound)
        let (newText, newSelection) = MarkdownFormat.apply(format, to: text, selection: lo..<hi)
        guard newText != text else { return }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        if tv.shouldChangeText(in: whole, replacementString: newText) {
            tv.textStorage?.replaceCharacters(in: whole, with: newText)
            tv.didChangeText()
            let a = newText.index(newText.startIndex, offsetBy: min(newSelection.lowerBound, newText.count))
            let b = newText.index(newText.startIndex, offsetBy: min(newSelection.upperBound, newText.count))
            tv.setSelectedRange(NSRange(a..<b, in: newText))
        }
        tv.window?.makeFirstResponder(tv)
    }

    func focus() { textView?.window?.makeFirstResponder(textView) }
}

/// The Markdown writing area: a real macOS text view (spelling, undo, the system's text services), in the
/// theme's colours, with smart quotes and dashes off so Markdown stays as typed.
struct KitMarkdownEditor: NSViewRepresentable {
    @Environment(\.theme) private var theme
    @Binding var text: String
    let controller: KitMarkdownEditorController
    var fontSize: CGFloat = 14

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = NSTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.textContainerInset = NSSize(width: 14, height: 12)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        scroll.documentView = tv
        controller.textView = tv
        context.coordinator.textView = tv
        style(tv)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.textView = tv
        style(tv)
        if tv.string != text {
            let selection = tv.selectedRange()
            context.coordinator.updating = true
            tv.string = text
            context.coordinator.updating = false
            tv.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
    }

    private func style(_ tv: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let font = NSFont.systemFont(ofSize: fontSize)
        let colour = NSColor(theme.text100)
        tv.font = font
        tv.textColor = colour
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph]
        tv.insertionPointColor = NSColor(theme.accentHover)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(theme.accent).withAlphaComponent(0.35)]
        tv.linkTextAttributes = [.foregroundColor: NSColor(theme.accentText)]
        tv.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KitMarkdownEditor
        weak var textView: NSTextView?
        var updating = false

        init(_ parent: KitMarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !updating, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// The formatting strip above the writing area (web: the md-toolbar): Heading, B I U S, lists, quote, code,
/// code block, rule, table, link. Each button is the shared `MarkdownFormat`, with its tooltip.
struct KitFormatToolbar: View {
    @Environment(\.theme) private var theme
    let controller: KitMarkdownEditorController

    private static let shortcuts: [MarkdownFormat: String] = [
        .bold: " (⌘B)", .italic: " (⌘I)", .underline: " (⌘U)", .strike: " (⇧⌘X)", .link: " (⌘K)",
        .h1: " (⌥⌘1)", .h2: " (⌥⌘2)", .h3: " (⌥⌘3)",
    ]

    /// Wraps onto a second line when the pane is narrow (web: flex-wrap), so it never makes the pane wider
    var body: some View {
        KitFlowLayout(spacing: 2) {
            Menu {
                ForEach([MarkdownFormat.h1, .h2, .h3], id: \.self) { f in
                    Button(f.label + (Self.shortcuts[f] ?? "")) { controller.apply(f) }
                }
            } label: {
                HStack(spacing: 2) {
                    Text("H").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(theme.textMuted)
                .frame(width: 34, height: 26)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .help("Heading")
            .accessibilityLabel("Heading")
            ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, formats in
                divider
                ForEach(formats, id: \.self) { f in
                    KitIconButton(systemImage: f.icon, label: f.label + (Self.shortcuts[f] ?? "")) { controller.apply(f) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private static let groups: [[MarkdownFormat]] = [
        [.bold, .italic, .underline, .strike], [.ul, .ol, .checklist, .quote], [.code, .codeblock, .hr, .table, .link],
    ]

    private var divider: some View {
        Rectangle().fill(theme.border3).frame(width: 1, height: 16).padding(.horizontal, 4).frame(height: 26)
    }
}
