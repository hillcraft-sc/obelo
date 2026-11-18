import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Entry point of the share extension: reads what was shared (a web page's URL and title, or
// text) and shows ShareView, themed like the app.

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        ShareKeyboard.dismiss = { [weak self] in self?.view.endEditing(true) }
        Task { await present(item: await readSharedItem()) }
    }

    private func present(item: SharedItem) async {
        let theme = Theme.resolve(AppGroup.appearance)
        let root = ShareView(item: item) { [weak self] message in self?.done(message) }
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.accent)
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func done(_ message: String?) {
        guard let message else {
            extensionContext?.cancelRequest(withError: NSError(domain: "Obelo", code: 0))
            return
        }
        // A short confirmation before the sheet closes
        let label = UILabel()
        label.text = "✓ " + message
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0.15, alpha: 0.95)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.frame = CGRect(x: 40, y: view.bounds.midY - 26, width: view.bounds.width - 80, height: 52)
        view.addSubview(label)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func readSharedItem() async -> SharedItem {
        var item = SharedItem()
        let inputs = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for input in inputs {
            if item.title == nil, let t = input.attributedContentText?.string, !t.isEmpty { item.title = t }
            for provider in input.attachments ?? [] {
                if item.url == nil, provider.canLoadObject(ofClass: URL.self),
                   let url = await loadURL(provider), !url.isFileURL {
                    item.url = url.absoluteString
                } else if item.text == nil, provider.canLoadObject(ofClass: String.self),
                          let text = await loadText(provider) {
                    item.text = text
                }
            }
        }
        // Safari passes the page title as the item's text; don't also treat it as capture text
        if item.url != nil, item.text == item.title { item.text = nil }
        return item
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { value, _ in continuation.resume(returning: value) }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { value, _ in continuation.resume(returning: value) }
        }
    }
}
