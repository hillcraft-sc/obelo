import AppKit
import SwiftUI
import WebKit

// Help's pieces (web: help/index.ejs): the contents list with the section in view marked, the shortcut table,
// and the page that draws the help text in the theme's colours.

/// The section names down the left; the one being read is marked (web: `.toc-link.active`)
struct KitContentsList: View {
    @Environment(\.theme) private var theme
    let sections: [(id: String, title: String)]
    let current: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                KitGroupLabel(text: "Contents").padding(.horizontal, 8).padding(.bottom, 6)
                ForEach(sections, id: \.id) { s in
                    Row(title: s.title, isCurrent: s.id == current) { onSelect(s.id) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contents")
    }

    private struct Row: View {
        @Environment(\.theme) private var theme
        @State private var hovering = false
        let title: String
        let isCurrent: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title).font(.system(size: 13))
                    .foregroundStyle(isCurrent ? theme.accentText : hovering ? theme.text300 : theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isCurrent ? theme.accent.opacity(0.12) : hovering ? theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .leading) {
                        if isCurrent { RoundedRectangle(cornerRadius: 1).fill(theme.accent).frame(width: 2).padding(.vertical, 3) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(isCurrent ? "\(title), current section" : title)
        }
    }
}

/// Shortcut rows in two columns: the name on the left, the keys as a key cap on the right
struct KitShortcutTable: View {
    @Environment(\.theme) private var theme
    let rows: [ShortcutGroup.Row]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 0) {
            ForEach(rows, id: \.self) { r in
                HStack(spacing: 12) {
                    Text(r.label).font(.system(size: 13)).foregroundStyle(theme.text400).lineLimit(2)
                    Spacer(minLength: 8)
                    KitKeyCap(text: r.keys)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { KitDivider() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.label), \(r.keys)")
            }
        }
    }
}

/// What the page is asked to look for
struct KitHelpFind: Equatable {
    let id: Int
    let text: String
    let backwards: Bool
}

/// The help text, drawn in a web view in this theme's colours. Links to a section scroll, links to a web address
/// open in the browser, everything else goes nowhere. It reports the section in view as you scroll.
struct KitHelpPage: NSViewRepresentable {
    @Environment(\.theme) private var theme
    let html: String
    @Binding var current: String
    @Binding var jump: String?
    var find: KitHelpFind?
    #if DEBUG
    var onReady: ((WKWebView) -> Void)?
    #endif

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "section")
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.onSection = { id in DispatchQueue.main.async { current = id } }
        #if DEBUG
        c.onReady = onReady
        #endif
        let key = "\(theme.id)\(theme.isDark ? "d" : "l")\(html.hashValue)"
        if c.loadedKey != key {
            c.loadedKey = key
            web.loadHTMLString(page, baseURL: nil)
        }
        if let id = jump {
            web.evaluateJavaScript("document.getElementById('\(id.filter { $0.isLetter || $0.isNumber || $0 == "-" })')?.scrollIntoView({behavior:'smooth'})")
            DispatchQueue.main.async { jump = nil }
        }
        if let find, find.id != c.lastFind {
            c.lastFind = find.id
            let configuration = WKFindConfiguration()
            configuration.backwards = find.backwards
            configuration.wraps = true
            configuration.caseSensitive = false
            web.find(find.text, configuration: configuration) { _ in }
        }
    }

    /// Tells the app which section is in view (the last one whose top has passed the top of the window)
    private static let script = """
    (function () {
      var last = '';
      function check() {
        var sections = document.querySelectorAll('section[id]');
        var active = sections.length ? sections[0].id : '';
        for (var i = 0; i < sections.length; i++) { if (sections[i].offsetTop - 80 <= window.scrollY) active = sections[i].id; }
        if (window.innerHeight + window.scrollY >= document.body.scrollHeight - 2 && sections.length) active = sections[sections.length - 1].id;
        if (active !== last) { last = active; window.webkit.messageHandlers.section.postMessage(active); }
      }
      window.addEventListener('scroll', check, { passive: true });
      window.addEventListener('load', check);
      check();
    })();
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var loadedKey = ""
        var lastFind = 0
        var onSection: (String) -> Void = { _ in }
        #if DEBUG
        var onReady: ((WKWebView) -> Void)?
        #endif

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let id = message.body as? String else { return }
            onSection(id)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            switch HelpLink.classify(url) {
            case .section(let id):
                let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
                _ = try? await webView.evaluateJavaScript("document.getElementById('\(safe)')?.scrollIntoView({behavior:'smooth'})")
            case .web(let u): NSWorkspace.shared.open(u)
            case .ignore: break
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if DEBUG
            onReady?(webView)
            #endif
        }
    }

    private func css(_ c: Color) -> String {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        return String(format: "rgba(%d,%d,%d,%.3f)", Int((n.redComponent * 255).rounded()), Int((n.greenComponent * 255).rounded()),
                      Int((n.blueComponent * 255).rounded()), n.alphaComponent)
    }

    /// The web's .help-content styles with this theme's colours
    private var page: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
          body { margin: 0; padding: 4px 28px 48px 4px; font-family: -apple-system, system-ui; background: transparent; }
          section { margin-bottom: 40px; scroll-margin-top: 8px; max-width: 760px; }
          section > div { background: \(css(theme.surface)); border: 1px solid \(css(theme.border1)); border-radius: 12px; padding: 20px; }
          h2 { font-size: 17px; font-weight: 700; color: \(css(theme.textPrimary)); margin: 0 0 12px; padding-bottom: 8px; border-bottom: 1px solid \(css(theme.border1)); }
          h3 { font-size: 14px; font-weight: 600; color: \(css(theme.text200)); margin: 20px 0 8px; }
          p, ul { font-size: 14px; color: \(css(theme.text400)); line-height: 1.65; margin: 0 0 12px; }
          ul { padding-left: 20px; }
          li { margin-bottom: 4px; }
          strong { color: \(css(theme.text200)); }
          a { color: \(css(theme.accentText)); text-decoration: none; }
          a:hover { text-decoration: underline; }
          code, .help-kbd { font-family: ui-monospace, monospace; font-size: 12px; background: \(css(theme.elevated)); border: 1px solid \(css(theme.border2));
                 border-radius: 4px; padding: 1px 5px; color: \(css(theme.text300)); }
          .help-kbd { display: inline-block; white-space: nowrap; }
          .sc-grid { display: grid; grid-template-columns: 1fr 1fr; column-gap: 24px; margin-top: 4px; }
          .sc-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 5px 0; border-bottom: 1px solid \(css(theme.border1)); }
          .sc-row span:first-child { font-size: 13px; color: \(css(theme.text400)); }
          [class*="grid"]:not(.sc-grid) { display: block; }
        </style></head><body>\(html)</body></html>
        """
    }
}
