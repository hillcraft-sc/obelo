import Foundation
import SwiftUI

// The Help module's logic, with no interface: the help text from the server (one copy, shared with the web and
// the other apps), which sections belong on a Mac, the Mac's own Keyboard Shortcuts section built from a list,
// the section being read, and what a link in the text should do. The Mac Help window is built on it. It talks
// to the server through `HelpAPI`, so tests can use a stub.

struct HelpContent: Decodable, Equatable {
    struct Section: Decodable, Hashable, Identifiable { let id: String; let title: String }
    let sections: [Section]
    let html: String
}

@MainActor
protocol HelpAPI {
    func help() async throws -> HelpContent
}

@MainActor
struct LiveHelpAPI: HelpAPI {
    func help() async throws -> HelpContent { try await APIClient.shared.get("/help") }
}

/// A named group of keyboard shortcuts (the Keyboard Shortcuts card and the `?` sheet)
struct ShortcutGroup: Hashable, Identifiable {
    struct Row: Hashable { let label: String; let keys: String }
    let title: String
    let rows: [Row]
    var id: String { title }
}

/// What a click on a link in the help text should do
enum HelpLink: Equatable {
    /// Scroll to a section of this page
    case section(String)
    /// Open in the default browser (an explanation that points outside, never a sign-in)
    case web(URL)
    case ignore

    static func classify(_ url: URL) -> HelpLink {
        if let fragment = url.fragment, !fragment.isEmpty, url.scheme == nil || url.scheme == "about" { return .section(fragment) }
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" { return .web(url) }
        return .ignore
    }
}

@MainActor @Observable
final class HelpStore {
    private let api: HelpAPI
    private(set) var content: HelpContent?
    private(set) var loaded = false
    var error: String?

    /// The section in view
    var current = ""
    /// "Scroll to this section", picked up by the page and cleared
    var jump: String?

    /// The words in the Find box, and a counter that changes whenever Find is asked to look (again)
    var findQuery = ""
    private(set) var findRequest = 0
    private(set) var findBackwards = false

    /// Sections that don't apply on a Mac: the phone's bottom bar, swipes and installing the website
    static let leftOut: Set<String> = ["mobile"]

    init(api: HelpAPI) { self.api = api }
    convenience init() { self.init(api: LiveHelpAPI()) }

    func load() async {
        do {
            let c = try await api.help()
            content = c; loaded = true; error = nil
            if current.isEmpty || !sections.contains(where: { $0.id == current }) { current = sections.first?.id ?? "" }
        } catch { self.error = error.localizedDescription }
    }

    // ── Sections ────────────────────────────────────────────────────────────

    static let shortcutsSection = HelpContent.Section(id: "shortcuts", title: "Keyboard Shortcuts")

    /// The contents list: the server's sections without the ones left out, with Keyboard Shortcuts (the Mac's own)
    /// after Global Search, where the web has it
    var sections: [HelpContent.Section] {
        guard let content else { return [] }
        var list = content.sections.filter { !Self.leftOut.contains($0.id) && $0.id != Self.shortcutsSection.id }
        let at = list.firstIndex { $0.id == "search" }.map { $0 + 1 } ?? list.count
        list.insert(Self.shortcutsSection, at: at)
        return list
    }

    func select(_ id: String) {
        current = id
        jump = id
    }

    // ── The page ────────────────────────────────────────────────────────────

    /// The server's text with the left-out sections taken out and the Mac's Keyboard Shortcuts section added
    func html(shortcuts: [ShortcutGroup]) -> String {
        guard let content else { return "" }
        return Self.page(from: content.html, shortcuts: shortcuts)
    }

    static func page(from html: String, shortcuts: [ShortcutGroup]) -> String {
        var out = html
        for id in leftOut { out = removeSection(id, from: out) }
        out = removeSection(shortcutsSection.id, from: out)
        let card = shortcutsHTML(shortcuts)
        if let r = sectionRange("search", in: out) {
            out.insert(contentsOf: "\n" + card, at: r.upperBound)
        } else {
            out += "\n" + card
        }
        return out
    }

    /// The range of `<section id="…"> … </section>` (sections don't nest in the help text)
    private static func sectionRange(_ id: String, in html: String) -> Range<String.Index>? {
        guard let start = html.range(of: "<section id=\"\(id)\"") else { return nil }
        guard let end = html.range(of: "</section>", range: start.upperBound..<html.endIndex) else { return nil }
        return start.lowerBound..<end.upperBound
    }

    private static func removeSection(_ id: String, from html: String) -> String {
        guard let r = sectionRange(id, in: html) else { return html }
        var out = html
        out.removeSubrange(r)
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The Mac's Keyboard Shortcuts card, in the same markup as the other sections
    static func shortcutsHTML(_ groups: [ShortcutGroup]) -> String {
        var h = "<section id=\"shortcuts\"><div><h2>Keyboard Shortcuts</h2>"
        h += "<p>Press <span class=\"help-kbd\">?</span> from any screen (when you are not typing) to open this list on its own. Single letters only work while no text box has the cursor.</p>"
        for g in groups {
            h += "<h3>\(escape(g.title))</h3><div class=\"sc-grid\">"
            for r in g.rows {
                h += "<div class=\"sc-row\"><span>\(escape(r.label))</span><span class=\"help-kbd\">\(escape(r.keys))</span></div>"
            }
            h += "</div>"
        }
        return h + "</div></section>"
    }

    // ── Find ────────────────────────────────────────────────────────────────

    /// Looks for the Find box's words (next match, or the one before)
    func find(backwards: Bool = false) {
        guard !findQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        findBackwards = backwards
        findRequest += 1
    }
}
