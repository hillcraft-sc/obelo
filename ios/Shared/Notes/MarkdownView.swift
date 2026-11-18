import SwiftUI

// Shared by the iPhone, iPad and Mac apps (moved here from the iPhone's Components, no change to how it
// draws). It reads Markdown for notes, tasks and reminders and draws it with the web's .prose styling.

// ── Markdown ─────────────────────────────────────────────────────────────────
// Renders note/task Markdown with the web's .prose styling (headings, lists, checklists,
// quotes, code, rules) and inline formatting via AttributedString.

struct MarkdownView: View {
    @Environment(\.theme) private var theme
    let text: String
    /// Set to make checklist items tickable: called with the item's line in `text` and its new state
    var onToggle: ((Int, Bool) -> Void)? = nil
    /// Whether the text can be selected with the pointer. Off where a click should start editing instead.
    var selectable = true

    /// One piece of the Markdown, as the renderer sees it (internal so the parser can be unit tested)
    enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, indent: Int)
        case numbered(String, String, indent: Int)
        case check(Bool, String, indent: Int, line: Int)
        case quote(String)
        case code(String)
        case rule
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(of: text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if selectable { content.textSelection(.enabled) } else { content.textSelection(.disabled) }
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            inline(s).font(.system(size: level == 1 ? 22 : level == 2 ? 19 : 16, weight: .semibold))
                .foregroundStyle(theme.text100).padding(.top, 6)
        case .paragraph(let s):
            inline(s).font(.system(size: 15)).foregroundStyle(theme.text300).lineSpacing(5)
        case .bullet(let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(theme.text300)
                inline(s).font(.system(size: 15)).foregroundStyle(theme.text300).lineSpacing(4)
            }
            .padding(.leading, CGFloat(indent) * 16 + 6)
        case .numbered(let n, let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(n).").foregroundStyle(theme.text300).monospacedDigit()
                inline(s).font(.system(size: 15)).foregroundStyle(theme.text300).lineSpacing(4)
            }
            .padding(.leading, CGFloat(indent) * 16 + 6)
        case .check(let done, let s, let indent, let line):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let box = Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: onToggle == nil ? 14 : 17)).foregroundStyle(done ? theme.accent : theme.textMuted)
                if let onToggle {
                    Button { onToggle(line, !done) } label: { box.frame(minWidth: 28, minHeight: 28) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(done ? "Done" : "Not done")
                        .accessibilityHint("Ticks or unticks this item")
                } else {
                    box
                }
                inline(s).font(.system(size: 15)).foregroundStyle(theme.text300)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let s):
            inline(s).font(.system(size: 15)).italic().foregroundStyle(theme.text400)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(theme.border3).frame(width: 3) }
        case .code(let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s).font(.system(size: 13, design: .monospaced)).foregroundStyle(theme.text200)
                    .padding(14)
            }
            .background(theme.page, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
        case .rule:
            Rectangle().fill(theme.border2).frame(height: 1).padding(.vertical, 8)
        }
    }

    private func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var attributed = try? AttributedString(markdown: s, options: options) else { return Text(s) }
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    attributed[run.range].font = .system(size: 13, design: .monospaced)
                    attributed[run.range].foregroundColor = theme.accentTextLight
                    attributed[run.range].backgroundColor = theme.elevated
                }
                if intent.contains(.stronglyEmphasized) { attributed[run.range].foregroundColor = theme.text100 }
            }
            if run.link != nil {
                attributed[run.range].foregroundColor = theme.accentText
                attributed[run.range].underlineStyle = .single
            }
        }
        return Text(attributed)
    }

    /// Splits Markdown text into blocks: headings, paragraphs, lists, checklist items (with their line
    /// numbers), quotes, code and rules
    static func blocks(of text: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for (lineNo, raw) in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let c = code { result.append(.code(c.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }

            let indent = (raw.prefix { $0 == " " }.count) / 2
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flush(); result.append(.heading(m.1.count, String(m.2)))
            } else if line.firstMatch(of: /^(-{3,}|\*{3,}|_{3,})$/) != nil {
                flush(); result.append(.rule)
            } else if let m = line.firstMatch(of: /^[-*+]\s+\[([ xX])\]\s+(.*)$/) {
                flush(); result.append(.check(m.1 != " ", String(m.2), indent: indent, line: lineNo))
            } else if let m = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flush(); result.append(.bullet(String(m.1), indent: indent))
            } else if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flush(); result.append(.numbered(String(m.1), String(m.2), indent: indent))
            } else if let m = line.firstMatch(of: /^>\s?(.*)$/) {
                flush()
                if case .quote(let prev) = result.last { result[result.count - 1] = .quote(prev + "\n" + m.1) }
                else { result.append(.quote(String(m.1))) }
            } else {
                paragraph.append(line)
            }
        }
        if let c = code { result.append(.code(c.joined(separator: "\n"))) }
        flush()
        return result
    }
}

extension MarkdownView {
    /// Ticks or unticks the checklist item on line `line` of Markdown `text`; nil if that line has none
    static func toggling(_ text: String, line: Int, done: Bool) -> String? {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.indices.contains(line),
              let m = lines[line].firstMatch(of: /^(\s*[-*+]\s+)\[[ xX]\]/) else { return nil }
        lines[line] = String(m.1) + (done ? "[x]" : "[ ]") + lines[line][m.range.upperBound...]
        return lines.joined(separator: "\n")
    }
}
