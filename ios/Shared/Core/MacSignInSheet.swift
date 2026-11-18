#if os(macOS)
import AppKit
import AuthenticationServices
import WebKit

// SSO sign-in for the Mac app, in a sheet on the app's own window. ASWebAuthenticationSession on the
// Mac opens the person's default browser, and third-party browsers (Brave, for one) take the sign-in
// but never hand the server's obelo://auth?code=… answer back to the app: the code was issued and
// lost, and the browser then reloaded the callback ("state mismatch"). Here the app's web view loads
// the same /auth/oidc page and catches the obelo:// navigation itself, whatever the default browser.
// It keeps its cookies (the default website data store), so a signed-in SSO session is reused.

@MainActor
final class MacSignInSheet: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// Keeps the sheet alive while it's open
    private static var current: MacSignInSheet?

    private let scheme: String
    private let panel: NSWindow
    private let web: WKWebView
    private weak var parent: NSWindow?
    private var continuation: CheckedContinuation<URL, Error>?

    static func run(url: URL, callbackScheme: String, parent: NSWindow) async throws -> URL {
        current?.finish(.failure(ASWebAuthErrorCanceled()))
        let sheet = MacSignInSheet(scheme: callbackScheme, parent: parent)
        current = sheet
        defer { if current === sheet { current = nil } }
        return try await withCheckedThrowingContinuation { continuation in
            sheet.continuation = continuation
            sheet.open(url)
        }
    }

    private init(scheme: String, parent: NSWindow) {
        self.scheme = scheme
        self.parent = parent
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Looks like Safari to the SSO provider; some refuse browsers they don't recognise
        config.applicationNameForUserAgent = "Version/27.0 Safari/605.1.15"
        web = WKWebView(frame: .zero, configuration: config)
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                         styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Sign in"
        panel.minSize = NSSize(width: 420, height: 480)
        web.navigationDelegate = self
        web.uiDelegate = self

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .push
        let container = NSView()
        for v in [web, cancel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: cancel.topAnchor, constant: -10),
            cancel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            cancel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        panel.contentView = container
    }

    private func open(_ url: URL) {
        if let parent { parent.beginSheet(panel) } else { panel.center(); panel.makeKeyAndOrderFront(nil) }
        web.load(URLRequest(url: url))
    }

    @objc private func cancelTapped() { finish(.failure(ASWebAuthErrorCanceled())) }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        web.stopLoading()
        if let parent, panel.sheetParent != nil { parent.endSheet(panel) } else { panel.orderOut(nil) }
        continuation.resume(with: result)
    }

    // The server's answer: obelo://auth?code=…
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.scheme == scheme {
            decisionHandler(.cancel)
            finish(.success(url))
            return
        }
        decisionHandler(.allow)
    }

    // A sign-in page that opens a new window (some providers do) loads here instead
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
}

/// The same "closed the sheet" error ASWebAuthenticationSession gives, so signIn treats both alike
private func ASWebAuthErrorCanceled() -> Error { ASWebAuthenticationSessionError(.canceledLogin) }
#endif
