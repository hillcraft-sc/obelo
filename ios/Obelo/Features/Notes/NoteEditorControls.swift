import SwiftUI

// The web note editor's controls (views/notes/_editor.ejs, public/js/note-editor.js): the Text/Draw and
// Write/Preview toggles, the Markdown toolbar, and the drawing toolbar. Used by NoteDetailView on every
// platform, so iPhone, iPad and Mac get the same tools as the web.

// ── Web-style pill toggle: "flex gap-0.5 p-0.5 bg-gray-800 rounded-md", active bg-gray-700 ─────────

struct PillSegment<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var small = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: small ? 12 : 14, weight: .medium))
                        .foregroundStyle(active ? theme.text100 : theme.textMuted)
                        .padding(.horizontal, small ? 10 : 12).padding(.vertical, small ? 4 : 6)
                        .background(active ? theme.h2 : .clear, in: RoundedRectangle(cornerRadius: small ? 5 : 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: small ? 7 : 8, style: .continuous))
        .fixedSize()
    }
}

/// The web's Markdown toolbar: heading menu, B I U S, lists, checklist, quote, code, code block, link,
/// rule, table. Scrolls sideways where it doesn't fit (iPhone).
struct MarkdownToolbar: View {
    @Environment(\.theme) private var theme
    let apply: (MarkdownFormat) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Menu {
                    ForEach([MarkdownFormat.h1, .h2, .h3], id: \.self) { f in Button(f.label) { apply(f) } }
                } label: {
                    Text("H").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.text400).frame(width: 30, height: 28)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Heading")
                divider
                ForEach([MarkdownFormat.bold, .italic, .underline, .strike], id: \.self, content: button)
                divider
                ForEach([MarkdownFormat.ul, .ol, .checklist, .quote], id: \.self, content: button)
                divider
                ForEach([MarkdownFormat.code, .codeblock, .link], id: \.self, content: button)
                divider
                ForEach([MarkdownFormat.hr, .table], id: \.self, content: button)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
        }
        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.border2, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(theme.border2).frame(width: 1, height: 16).padding(.horizontal, 3)
    }

    private func button(_ f: MarkdownFormat) -> some View {
        Button { apply(f) } label: {
            Image(systemName: f.icon).font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text400)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.label)
        .help(f == .bold ? "Bold (⌘B)" : f == .italic ? "Italic (⌘I)" : f.label)
        // The web's Ctrl/⌘+B and ⌘+I
        .keyboardShortcut(f == .bold ? KeyboardShortcut("b") : f == .italic ? KeyboardShortcut("i") : nil)
    }
}

// ── Drawing toolbar: colours, S/M/L, eraser, undo, clear ───────────────────────────────────────────

struct DrawingToolbar: View {
    @Environment(\.theme) private var theme
    @Binding var color: String
    @Binding var size: Double
    @Binding var erasing: Bool
    let paper: DrawingPaper   // the pen swatches show the shade you get on this paper
    let canUndo: Bool
    let undo: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DrawingRenderer.colors, id: \.self) { c in
                Button { color = c; erasing = false } label: {
                    Circle().fill(Color(hex: paper.ink(c))).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(theme.accent, lineWidth: !erasing && color == c ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(["#f1f5f9": "White", "#93c5fd": "Blue", "#fca5a5": "Red", "#86efac": "Green"][c] ?? c)
            }
            Rectangle().fill(theme.border2).frame(width: 1, height: 18)
            ForEach(DrawingRenderer.sizes, id: \.0) { label, width in
                Button { size = width } label: {
                    Text(label)
                        .font(.system(size: 12, weight: size == width ? .semibold : .regular))
                        .foregroundStyle(size == width ? theme.text100 : theme.text400)
                        .frame(width: 26, height: 26)
                        .background(size == width ? theme.h2 : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(theme.border2).frame(width: 1, height: 18)
            Button { erasing.toggle() } label: {
                Image(systemName: "eraser")
                    .foregroundStyle(erasing ? theme.accentText : theme.text400)
                    .frame(width: 30, height: 26)
                    .background(erasing ? theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eraser")
            Button(action: undo) { Image(systemName: "arrow.uturn.backward").foregroundStyle(theme.text400) }
                .buttonStyle(.plain).disabled(!canUndo).accessibilityLabel("Undo")
            Button(action: clear) { Image(systemName: "xmark").foregroundStyle(theme.text400) }
                .buttonStyle(.plain).disabled(!canUndo).accessibilityLabel("Clear")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.elevated)
    }
}
