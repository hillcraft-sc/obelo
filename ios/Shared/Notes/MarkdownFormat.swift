import SwiftUI

// ── Markdown formatting, the same edits as the web's fmt() ─────────────────────────────────────────

enum MarkdownFormat: CaseIterable {
    case h1, h2, h3, bold, italic, underline, strike, ul, ol, checklist, quote, code, codeblock, link, hr, table

    /// Applies the format to `text` with `selection` (character offsets). Returns the new text and the
    /// new selection, as the web does: the inserted placeholder or the formatted text is selected.
    static func apply(_ format: MarkdownFormat, to text: String, selection: Range<Int>) -> (String, Range<Int>) {
        let chars = Array(text)
        let start = min(max(0, selection.lowerBound), chars.count)
        let end = min(max(start, selection.upperBound), chars.count)
        let before = String(chars[..<start]), sel = String(chars[start..<end]), after = String(chars[end...])

        func wrap(_ open: String, _ close: String, _ placeholder: String) -> (String, Range<Int>) {
            if !sel.isEmpty {
                return (before + open + sel + close + after, start..<(start + open.count + sel.count + close.count))
            }
            let s = start + open.count
            return (before + open + placeholder + close + after, s..<(s + placeholder.count))
        }
        func prefixLines(_ prefix: String) -> (String, Range<Int>) {
            if !sel.isEmpty {
                let lines = sel.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }.joined(separator: "\n")
                return (before + lines + after, start..<(start + lines.count))
            }
            let ins = prefix + "text"
            return (before + ins + after, (start + prefix.count)..<(start + ins.count))
        }
        let atLineStart = before.isEmpty || before.hasSuffix("\n")

        switch format {
        case .bold: return wrap("**", "**", "bold text")
        case .italic: return wrap("*", "*", "italic text")
        case .underline: return wrap("<ins>", "</ins>", "underlined text")
        case .strike: return wrap("~~", "~~", "strikethrough")
        case .code: return wrap("`", "`", "code")
        case .h1: return prefixLines("# ")
        case .h2: return prefixLines("## ")
        case .h3: return prefixLines("### ")
        case .ul: return prefixLines("- ")
        case .ol: return prefixLines("1. ")
        case .quote: return prefixLines("> ")
        case .checklist:
            // Selected checklist lines are ticked or unticked; anything else becomes a checklist
            let lines = sel.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if !sel.isEmpty, lines.contains(where: { $0.hasPrefix("- [ ] ") || $0.hasPrefix("- [x] ") }) {
                let toggled = lines.map { l in
                    l.hasPrefix("- [ ] ") ? "- [x] " + l.dropFirst(6) : l.hasPrefix("- [x] ") ? "- [ ] " + l.dropFirst(6) : l
                }.joined(separator: "\n")
                return (before + toggled + after, start..<(start + toggled.count))
            }
            return prefixLines("- [ ] ")
        case .hr:
            let ins = (atLineStart ? "" : "\n") + "\n---\n\n"
            return (before + ins + after, (start + ins.count)..<(start + ins.count))
        case .codeblock:
            let body = sel.isEmpty ? "code here" : sel
            return (before + "\n```\n" + body + "\n```\n" + after, (start + 5)..<(start + 5 + body.count))
        case .link:
            let label = sel.isEmpty ? "link text" : sel
            let urlStart = start + label.count + 3
            return (before + "[" + label + "](url)" + after, urlStart..<(urlStart + 3))
        case .table:
            let nl = atLineStart ? "" : "\n"
            let tpl = nl + "\n| Header 1 | Header 2 | Header 3 |\n|----------|----------|----------|\n| Cell     | Cell     | Cell     |\n\n"
            let s = start + nl.count + 3
            return (before + tpl + after, s..<(s + 8))
        }
    }

    var label: String {
        switch self {
        case .h1: "Heading 1"; case .h2: "Heading 2"; case .h3: "Heading 3"
        case .bold: "Bold"; case .italic: "Italic"; case .underline: "Underline"; case .strike: "Strikethrough"
        case .ul: "Bullet list"; case .ol: "Numbered list"; case .checklist: "Checklist"; case .quote: "Blockquote"
        case .code: "Inline code"; case .codeblock: "Code block"; case .link: "Link"; case .hr: "Horizontal rule"
        case .table: "Insert table"
        }
    }

    var icon: String {
        switch self {
        case .h1, .h2, .h3: "textformat.size"
        case .bold: "bold"; case .italic: "italic"; case .underline: "underline"; case .strike: "strikethrough"
        case .ul: "list.bullet"; case .ol: "list.number"; case .checklist: "checklist"; case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"; case .codeblock: "curlybraces.square"
        case .link: "link"; case .hr: "minus"; case .table: "tablecells"
        }
    }
}

/// The text editor's selection as character offsets (end of the text when there's none)
func characterRange(of selection: TextSelection?, in text: String) -> Range<Int> {
    let n = text.count
    guard let selection, case .selection(let r) = selection.indices,
          r.lowerBound >= text.startIndex, r.upperBound <= text.endIndex else { return n..<n }
    let lo = text.distance(from: text.startIndex, to: r.lowerBound)
    let hi = text.distance(from: text.startIndex, to: r.upperBound)
    return lo..<hi
}

func selectionAt(_ range: Range<Int>, in text: String) -> TextSelection {
    let n = text.count
    let lo = text.index(text.startIndex, offsetBy: min(range.lowerBound, n))
    let hi = text.index(text.startIndex, offsetBy: min(range.upperBound, n))
    return TextSelection(range: lo..<hi)
}
