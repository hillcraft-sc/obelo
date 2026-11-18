import SwiftUI

// AI Chat — views/ai/index.ejs: ask questions about your own data. Read-only; the server
// builds the context (private and locked notes are never sent) and keeps the thread in the
// session, so this device has its own conversation.

struct AIChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var error: String?
    @State private var loaded = false
    @State private var confirmClear = false
    @FocusState private var inputFocused: Bool

    private static let suggestions = [
        "What tasks are slipping this week?",
        "What did I flag for review?",
        "How have my steps been lately?",
        "What books am I tracking?",
    ]

    private var aiEnabled: Bool { app.me?.aiEnabled ?? false }

    var body: some View {
        // Exactly the height the window gives: the thread fits between the header and the input
        // instead of asking for its full height (on the Mac that pushed the whole window's content,
        // sidebar included, up out of view and the input off the bottom)
        GeometryReader { geo in
            column.frame(width: geo.size.width, height: geo.size.height)
        }
        .background(theme.page)
    }

    private var column: some View {
        VStack(spacing: 0) {
            header
            if !aiEnabled {
                Banner(kind: .warning, text: "AI isn't configured on this server. The server admin can enable it by setting the AI_* variables in .env.")
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            // The thread takes whatever height is left, and no more: on the Mac a taller-than-window
            // column pushed the whole window's content (sidebar included) up out of view
            thread
                .frame(minHeight: 0, maxHeight: .infinity)
            inputBar
        }
        .frame(maxWidth: 672)
        .frame(maxWidth: .infinity)
        .background(theme.page)
        .task {
            guard !loaded else { return }
            loaded = true
            struct R: Decodable { let messages: [ChatMessage] }
            if let r: R = try? await APIClient.shared.get("/ai") { messages = r.messages }
            #if DEBUG
            // Simulator testing: `-chatSend "question"` sends a message on open
            if let q = UserDefaults.standard.string(forKey: "chatSend") { input = q; send() }
            #endif
        }
        .confirmationDialog("Clear this conversation?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear chat", role: .destructive) {
                withAnimation { messages = [] }
                Task { try? await APIClient.shared.post("/ai/clear") }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            PageHeader(title: "AI Chat", subtitle: "Ask anything about your tasks, notes, reminders or calendar.", pageName: true)
            if !messages.isEmpty {
                Button { confirmClear = true } label: {
                    Text("Clear chat").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 16)
    }

    // ── Thread ───────────────────────────────────────────────────────────────

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if messages.isEmpty && !sending { emptyState }
                    ForEach(messages) { bubble($0).id($0.id) }
                    if sending { TypingDots().frame(maxWidth: .infinity, alignment: .leading).id("typing") }
                    if let error {
                        Text(error).font(.system(size: 14)).foregroundStyle(Color(hex: "#fca5a5"))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color(hex: "#450a0a"), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#991b1b"), lineWidth: 1))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("error")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(messages.isEmpty ? .center : .bottom)
            .onChange(of: messages.count) { scrollToEnd(proxy) }
            .onChange(of: sending) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if sending { proxy.scrollTo("typing", anchor: .bottom) }
            else if error != nil { proxy.scrollTo("error", anchor: .bottom) }
            else if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("✦").font(.system(size: 22)).foregroundStyle(theme.accentText)
                .frame(width: 48, height: 48)
                .background(theme.accentSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accentBorder9, lineWidth: 1))
            VStack(spacing: 4) {
                Text("Ask me about your data").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text400)
                Text("Tasks, notes, reminders, calendar — all in context").font(.system(size: 12)).foregroundStyle(theme.textMuted)
            }
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { q in
                    Button {
                        input = q
                        inputFocused = true
                    } label: {
                        Text(q).font(.system(size: 12)).foregroundStyle(theme.text400)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border1, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 384)
            .padding(.top, 8)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        if m.role == "user" {
            HStack {
                Spacer(minLength: 56)
                Text(m.content)
                    .font(.system(size: 14)).foregroundStyle(theme.onAccent).lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(theme.accent, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 4))
            }
        } else {
            HStack {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(m.content)
                        .font(.system(size: 14)).foregroundStyle(theme.text100).lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(theme.elevated, in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16))
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16).stroke(theme.border2, lineWidth: 1))
                    if let remaining = m.remaining {
                        Text("\(remaining) messages remaining today").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }

    // ── Input ────────────────────────────────────────────────────────────────

    @ViewBuilder private var inputField: some View {
        TextField("", text: $input, prompt: Text("Ask anything…").foregroundStyle(theme.placeholder), axis: .vertical)
            .lineLimit(1...5)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            inputField
                .font(.system(size: 14))
                .foregroundStyle(theme.textPrimary)
                .focused($inputFocused)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inputFocused ? theme.accentHover : theme.border2, lineWidth: 1))
                .disabled(!aiEnabled)
            Button(action: send) {
                Image(systemName: "paperplane.fill").font(.system(size: 15)).foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableStyle())
            .disabled(sending || !aiEnabled || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(sending || !aiEnabled ? 0.5 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16).padding(.top, 8)
        // Clear the iPhone's bottom bar, which the keyboard covers while typing
        .padding(.bottom, hasBottomBar && !inputFocused ? 74 : 12)
        .animation(.easeOut(duration: 0.2), value: inputFocused)
    }

    /// The iPhone layout has a bottom bar under this screen; the Mac and full-width iPad don't
    private var hasBottomBar: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        error = nil
        withAnimation { messages.append(ChatMessage(role: "user", content: text)) }
        sending = true
        Task {
            defer { sending = false }
            do {
                struct R: Decodable { let reply: String; let remaining: Int }
                let r: R = try await APIClient.shared.post("/ai/message", ["message": text])
                withAnimation { messages.append(ChatMessage(role: "assistant", content: r.reply, remaining: r.remaining)) }
            } catch {
                // The server saved nothing, so put the question back to retry
                withAnimation {
                    if messages.last?.content == text { messages.removeLast() }
                    self.error = error.localizedDescription
                }
                if input.isEmpty { input = text }
            }
        }
    }
}

/// The web's three bouncing dots
private struct TypingDots: View {
    @Environment(\.theme) private var theme
    @State private var up = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(theme.textMuted).frame(width: 8, height: 8)
                    .offset(y: up ? -4 : 0)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: up)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(theme.elevated, in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16).stroke(theme.border2, lineWidth: 1))
        .onAppear { up = true }
        .accessibilityLabel("Thinking")
    }
}
