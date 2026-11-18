import SwiftUI
import WebKit

// Help — the web's help page text (views/help/index.ejs, via GET /api/v1/help) shown in the
// app's theme, with a section picker in place of the web's sidebar contents. One copy of the
// help text means the app never drifts from the web. Links inside it don't navigate anywhere.

struct HelpView: View {
    @Environment(\.theme) private var theme

    struct Section: Decodable, Hashable { let id: String; let title: String }
    struct Help: Decodable { let sections: [Section]; let html: String }

    @State private var help: Help?
    @State private var error: String?
    @State private var section = ""
    @State private var jump: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Help", subtitle: "How everything in Obelo works.", pageName: true)
                if let help {
                    SectionTabs(tabs: help.sections.map { SectionTab(key: $0.id, label: $0.title) }, selection: Binding(
                        get: { section },
                        set: { section = $0; jump = $0 }
                    ))
                }
            }
            .padding(.horizontal, 16).padding(.top, 16)

            if let help {
                HelpWebView(html: help.html, theme: theme, jump: $jump)
                    .padding(.bottom, 64) // clear the bottom bar
            } else if let error {
                Banner(kind: .error, text: error).padding(16)
                Spacer()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.page)
        .task {
            guard help == nil else { return }
            do {
                let h: Help = try await APIClient.shared.get("/help")
                help = h
                section = h.sections.first?.id ?? ""
            } catch { self.error = error.localizedDescription }
        }
    }
}

#if os(iOS)
private typealias WebRepresentable = UIViewRepresentable
#else
private typealias WebRepresentable = NSViewRepresentable
#endif

private struct HelpWebView: WebRepresentable {
    let html: String
    let theme: Theme
    @Binding var jump: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { make(context) }
    func updateUIView(_ web: WKWebView, context: Context) { update(web, context) }
    #else
    func makeNSView(context: Context) -> WKWebView { make(context) }
    func updateNSView(_ web: WKWebView, context: Context) { update(web, context) }
    #endif

    private func make(_ context: Context) -> WKWebView {
        let web = WKWebView()
        #if os(iOS)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        #else
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        #endif
        web.navigationDelegate = context.coordinator
        web.loadHTMLString(page, baseURL: nil)
        context.coordinator.loadedTheme = theme.id + (theme.isDark ? "d" : "l")
        return web
    }

    private func update(_ web: WKWebView, _ context: Context) {
        let themeKey = theme.id + (theme.isDark ? "d" : "l")
        if context.coordinator.loadedTheme != themeKey {
            context.coordinator.loadedTheme = themeKey
            web.loadHTMLString(page, baseURL: nil)
        }
        if let id = jump {
            web.evaluateJavaScript("document.getElementById('\(id)')?.scrollIntoView({behavior:'smooth'})")
            DispatchQueue.main.async { jump = nil }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedTheme = ""
        // Only the help page itself loads; links in the text go nowhere
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other ? .allow : .cancel
        }
    }

    private func css(_ c: Color) -> String { c.hexString }

    /// The web's .help-content styles, with this theme's colours
    private var page: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>
          :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
          body { margin: 0; padding: 4px 16px 32px; font: -apple-system-body; font-family: -apple-system, system-ui; background: transparent; }
          section { margin-bottom: 20px; scroll-margin-top: 8px; }
          section > div { background: \(css(theme.surface)); border: 1px solid \(css(theme.border1)); border-radius: 12px; padding: 18px; }
          h2 { font-size: 17px; font-weight: 700; color: \(css(theme.textPrimary)); margin: 0 0 12px; padding-bottom: 8px; border-bottom: 1px solid \(css(theme.border1)); }
          h3 { font-size: 14px; font-weight: 600; color: \(css(theme.text200)); margin: 18px 0 8px; }
          p, ul { font-size: 14px; color: \(css(theme.text400)); line-height: 1.6; margin: 0 0 10px; }
          ul { padding-left: 20px; }
          li { margin-bottom: 4px; }
          strong { color: \(css(theme.text200)); }
          a { color: \(css(theme.accentText)); text-decoration: none; }
          code, .help-kbd { font-family: ui-monospace, monospace; font-size: 12px; background: \(css(theme.elevated)); border: 1px solid \(css(theme.border2));
                 border-radius: 4px; padding: 1px 5px; color: \(css(theme.text300)); }
          .help-kbd { display: inline-block; }
          [class*="grid"] { display: block; }
        </style></head><body>\(html)</body></html>
        """
    }
}
