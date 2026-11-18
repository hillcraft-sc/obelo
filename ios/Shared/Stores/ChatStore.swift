import Foundation
import SwiftUI

// The AI Chat module's logic, with no interface: the thread, the message being typed, sending (your message
// shows at once; a failed send takes it back and puts the text back in the box), the "messages remaining
// today" figure, and clearing. The Mac screen is built on it. It talks to the server through `ChatAPI`, so
// tests can use a stub. Whether AI is set up comes from `me.aiEnabled`, which the screen passes in.

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String
    let content: String
    var remaining: Int?

    enum CodingKeys: String, CodingKey { case role, content }

    var isUser: Bool { role == "user" }
}

struct ChatReply: Equatable {
    let reply: String
    let remaining: Int
}

@MainActor
protocol ChatAPI {
    func thread() async throws -> [ChatMessage]
    func send(_ message: String) async throws -> ChatReply
    func clear() async throws
}

@MainActor
struct LiveChatAPI: ChatAPI {
    private var api: APIClient { .shared }
    private struct Thread: Decodable { let messages: [ChatMessage] }
    private struct Reply: Decodable { let reply: String; let remaining: Int }

    func thread() async throws -> [ChatMessage] { (try await api.get("/ai") as Thread).messages }
    func send(_ message: String) async throws -> ChatReply {
        let r: Reply = try await api.post("/ai/message", ["message": message])
        return ChatReply(reply: r.reply, remaining: r.remaining)
    }
    func clear() async throws { try await api.post("/ai/clear") }
}

@MainActor @Observable
final class ChatStore {
    private let api: ChatAPI

    private(set) var messages: [ChatMessage] = []
    private(set) var loaded = false
    private(set) var sending = false
    /// What is typed in the box
    var input = ""
    var error: String?

    /// The four questions the empty thread offers (the web's list)
    static let suggestions = [
        "What tasks are slipping this week?",
        "What did I flag for review?",
        "How have my steps been lately?",
        "What books am I tracking?",
    ]

    init(api: ChatAPI) { self.api = api }
    convenience init() { self.init(api: LiveChatAPI()) }

    var isEmpty: Bool { messages.isEmpty }

    /// Send is allowed: AI is on, nothing is waiting, and the box has words
    func canSend(aiEnabled: Bool) -> Bool {
        aiEnabled && !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        do { messages = try await api.thread(); loaded = true; error = nil }
        catch { self.error = error.localizedDescription }
    }

    /// A suggestion goes in the box and is not sent
    func use(suggestion: String) { input = suggestion }

    /// Sends what is in the box. Returns false when nothing was sent (empty, already waiting, or the server refused).
    @discardableResult
    func send() async -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return false }
        input = ""
        error = nil
        let mine = ChatMessage(role: "user", content: text)
        messages.append(mine)
        sending = true
        defer { sending = false }
        do {
            let r = try await api.send(text)
            messages.append(ChatMessage(role: "assistant", content: r.reply, remaining: r.remaining))
            return true
        } catch {
            // The server saved nothing, so take the question back and put the words back to try again
            messages.removeAll { $0.id == mine.id }
            if input.isEmpty { input = text }
            self.error = error.localizedDescription
            return false
        }
    }

    func clear() async {
        do { try await api.clear(); messages = []; error = nil }
        catch { self.error = error.localizedDescription }
    }

    // ── Wording ─────────────────────────────────────────────────────────────

    static func remainingText(_ n: Int) -> String { "\(n) messages remaining today" }
    static let notConfigured = "AI isn't configured on this server. Ask the server admin to turn it on."
}
