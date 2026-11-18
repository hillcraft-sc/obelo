import AppKit
import SwiftUI

/// What the menu bar can ask of the AI Chat screen (Edit ▸ Clear Chat…)
struct ChatActions {
    let clear: () -> Void
}

extension FocusedValues {
    @Entry var chatActions: ChatActions?
}

/// AI Chat: the thread, the four suggestions, and the message box.
/// The server keeps the thread for this device's sign-in; nothing here changes your data.
struct AIChatScreen: View {
    @Environment(AppState.self) private var app
    @Environment(KitToastCenter.self) private var toast
    @Environment(\.theme) private var theme
    @State private var store = Self.makeStore()
    @State private var focusInput = false
    @State private var confirmClear = false

    private static func makeStore() -> ChatStore {
        #if DEBUG
        MacDebug.chatStore()
        #else
        ChatStore()
        #endif
    }

    private var aiEnabled: Bool { app.me?.aiEnabled ?? false }
    private let bottom = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                KitPageHeading(title: "AI Chat", description: "Ask anything about your tasks, notes, reminders or calendar.") {
                    if !store.isEmpty {
                        Button("Clear chat") { confirmClear = true }
                            .buttonStyle(KitButtonStyle(.secondary, small: true))
                            .help("Clear chat (⇧⌘⌫)")
                    }
                }
                if !aiEnabled { KitBanner(kind: .warn, text: ChatStore.notConfigured) }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
            thread
            VStack(spacing: 8) {
                if let message = store.error { KitBanner(kind: .error, text: message) }
                KitChatInput(placeholder: "Ask anything…", text: $store.input, focusRequest: $focusInput,
                             canSend: store.canSend(aiEnabled: aiEnabled), onSend: send)
                    .disabled(!aiEnabled)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
        }
        .frame(maxWidth: KitWidth.chat)
        .frame(maxWidth: .infinity)
        .background(theme.page)
        .task {
            await store.load()
            focusInput = true
            #if DEBUG
            // Testing: `-chatInput "text"` puts words in the box
            if let t = UserDefaults.standard.string(forKey: "chatInput") { store.input = t }
            if UserDefaults.standard.bool(forKey: "chatSend") { Task { await store.send() } }
            #endif
        }
        .onChange(of: app.dataVersion) { Task { await store.load() } }
        .focusedSceneValue(\.chatActions, ChatActions(clear: { if !store.isEmpty { confirmClear = true } }))
        .kitConfirm("Clear this chat?", isPresented: $confirmClear, confirmLabel: "Clear chat", destructive: true) {
            Task { await store.clear(); focusInput = true }
        }
    }

    // ── The thread ──────────────────────────────────────────────────────────

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if store.isEmpty && !store.sending {
                        empty
                    } else {
                        ForEach(store.messages) { m in
                            KitChatBubble(text: m.content, isUser: m.isUser, remaining: m.remaining.map(ChatStore.remainingText)) { copy(m.content) }
                        }
                        if store.sending { KitTypingDots() }
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
            }
            .scrollEdgeEffectHidden(true, for: .top)
            .onChange(of: store.messages.count) { scrollToEnd(proxy) }
            .onChange(of: store.sending) { scrollToEnd(proxy) }
            .onChange(of: store.loaded) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottom, anchor: .bottom) }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Text("✦").font(.system(size: 24)).foregroundStyle(theme.accentText)
                .frame(width: 48, height: 48)
                .background(theme.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.accent.opacity(0.4)))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Ask me about your data").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text400)
                Text("Tasks, notes, reminders, calendar — all in context").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
            VStack(spacing: 8) {
                ForEach(ChatStore.suggestions, id: \.self) { q in
                    Button { store.use(suggestion: q); focusInput = true } label: {
                        Text(q).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(KitButtonStyle(.secondary, small: true))
                    .disabled(!aiEnabled)
                }
            }
            .frame(maxWidth: 384)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    private func send() {
        guard store.canSend(aiEnabled: aiEnabled) else { return }
        Task { await store.send(); focusInput = true }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toast.show("Copied")
    }
}
