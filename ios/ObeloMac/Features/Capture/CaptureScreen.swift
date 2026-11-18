import SwiftUI

/// Capture (web: capture/index.ejs): type anything, get a suggestion, check it, save it. The store is
/// owned by the shell, so what you typed and an unsaved suggestion stay while you visit other screens.
struct CaptureScreen: View {
    @Environment(AppState.self) private var app
    @Environment(MacRouter.self) private var router
    @Environment(KitToastCenter.self) private var toast
    @Environment(\.theme) private var theme
    let store: CaptureStore
    @State private var focusBox = false

    private var aiOn: Bool { app.me?.aiEnabled ?? true }

    private static let placeholder = """
    remind me to call the dentist tuesday 3pm
    grocery list: milk, eggs, bread, pasta
    bookmark reactjs.org — React docs
    note - ideas for the weekend trip, tag travel
    book rec: four thousand weeks by oliver burkeman
    """

    var body: some View {
        KitPage(width: KitWidth.form) {
            VStack(alignment: .leading, spacing: 20) {
                KitPageHeading(title: "Capture", description: "Type anything — AI will figure it out.")
                if !aiOn {
                    KitBanner(kind: .neutral, text: "AI isn't set up on this server, so Capture saves what you type as a note. To turn on AI, the server admin sets the AI_* variables in .env.")
                }
                if let error = store.error { KitBanner(kind: .error, text: error) }
                if store.draft == nil {
                    inputForm
                } else {
                    CaptureSuggestionCard(store: store) { Task { await save() } }
                }
            }
        }
        .task {
            if let text = router.captureText {
                store.prefill(text)
                router.captureText = nil
            }
            if store.draft == nil { focusBox = true }
        }
    }

    // ── Step one: the box ───────────────────────────────────────────────────

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            KitTextArea(placeholder: Self.placeholder, text: Binding(get: { store.raw }, set: { store.raw = $0 }),
                        minHeight: 110, focusRequest: $focusBox)
            if aiOn {
                KitFieldLabel(text: "Type") {
                    VStack(alignment: .leading, spacing: 6) {
                        KitPillSelector(options: [(value: "auto", label: "Auto")] + CaptureTypes.all.map { (value: $0, label: CaptureTypes.label($0)) },
                                        selection: Binding(get: { store.chosenType ?? "auto" },
                                                           set: { store.chosenType = $0 == "auto" ? nil : $0 }),
                                        label: "Type")
                        Text(store.chosenType == nil ? "Auto lets the AI decide." : "The AI fills in the details for a \(CaptureTypes.label(store.chosenType ?? "").lowercased()).")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            Button(store.processing ? "Processing…" : (aiOn ? "Process with AI" : "Save as note")) { Task { await store.process() } }
                .buttonStyle(KitButtonStyle(.primary, busy: store.processing, fullWidth: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.canProcess)
                .help("⌘Return")
        }
    }

    // ── Saving ──────────────────────────────────────────────────────────────

    /// Saves, then opens what was made, as the web and the iPhone do. Back returns here.
    private func save() async {
        guard let saved = await store.save() else { return }
        toast.show("Saved \(CaptureTypes.label(saved.type))")
        app.dataChanged()
        switch saved.type {
        case "task": router.open(.tasks(view: nil, task: saved.id))
        case "reminder": router.open(.reminder(saved.id))
        case "list": router.open(.list(saved.id))
        case "bookmark": router.open(.module("bookmarks"))
        default: router.open(.note(saved.id))
        }
    }
}
