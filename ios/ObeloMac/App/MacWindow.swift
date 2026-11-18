import AppKit
import SwiftUI

/// Sets up the main window: the title bar takes the page colour (no grey strip), the content runs up
/// under the traffic lights (SwiftUI keeps it clear of them), and the size and position are remembered.
struct MacWindowConfigurator: NSViewRepresentable {
    static let identifier = NSUserInterfaceItemIdentifier("obelo.main")

    /// The main window. SwiftUI gives its own identifier ("main-AppWindow-1", from the scene's id) and may
    /// replace ours, so both count.
    static func isMain(_ window: NSWindow) -> Bool {
        window.identifier == identifier || window.identifier?.rawValue.hasPrefix("main-AppWindow") == true
    }
    let page: Color

    func makeNSView(context: Context) -> NSView { WindowView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowView)?.page = NSColor(page)
    }

    private final class WindowView: NSView {
        var page: NSColor = .windowBackgroundColor { didSet { apply() } }

        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = MacWindowConfigurator.identifier
            window.styleMask.insert(.fullSizeContentView)
            window.setFrameAutosaveName("ObeloMainWindow")
            apply()
            // The system redraws the title bar when the app goes to the background and comes back
            // (a title, a lighter strip); set it again each time
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                }
            }
        }

        private func apply() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = page
        }
    }
}
