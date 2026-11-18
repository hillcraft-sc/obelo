import Foundation
import Testing
@testable import ObeloShared

@MainActor
final class StubChatAPI: ChatAPI {
    struct Failure: LocalizedError { var errorDescription: String? { "Daily limit of 50 messages reached. Resets at midnight." } }
    var history: [ChatMessage] = []
    var calls: [String] = []
    var failNext = false
    var remaining = 49

    func thread() async throws -> [ChatMessage] { calls.append("thread"); if failNext { failNext = false; throw Failure() }; return history }
    func send(_ message: String) async throws -> ChatReply {
        calls.append("send \(message)")
        if failNext { failNext = false; throw Failure() }
        defer { remaining -= 1 }
        return ChatReply(reply: "Answer to: \(message)", remaining: remaining)
    }
    func clear() async throws { calls.append("clear"); if failNext { failNext = false; throw Failure() }; history = [] }
}

@MainActor
struct ChatStoreTests {
    private func make(_ history: [ChatMessage] = []) -> (ChatStore, StubChatAPI) {
        let api = StubChatAPI(); api.history = history
        return (ChatStore(api: api), api)
    }

    @Test func loadsTheThreadWithoutRemainingFigures() async throws {
        let json = "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"},{\"role\":\"assistant\",\"content\":\"hello\"}]}"
        struct T: Decodable { let messages: [ChatMessage] }
        let loaded = try JSONDecoder().decode(T.self, from: Data(json.utf8)).messages
        let (s, _) = make(loaded)
        #expect(s.isEmpty && !s.loaded)
        await s.load()
        #expect(s.loaded && s.messages.map(\.content) == ["hi", "hello"])
        #expect(s.messages.map(\.isUser) == [true, false])
        #expect(s.messages.allSatisfy { $0.remaining == nil }, "older replies carry no figure, as on the web")
    }

    @Test func sendingAddsYourMessageAndTheReply() async {
        let (s, api) = make()
        s.input = "  What is due?  "
        let ok = await s.send()
        #expect(ok)
        #expect(api.calls == ["send What is due?"])
        #expect(s.messages.map(\.content) == ["What is due?", "Answer to: What is due?"])
        #expect(s.messages.last?.remaining == 49)
        #expect(s.input.isEmpty && !s.sending && s.error == nil)
    }

    @Test func theRemainingFigureCountsDown() async {
        let (s, _) = make()
        s.input = "a"; await s.send()
        s.input = "b"; await s.send()
        #expect(s.messages.compactMap(\.remaining) == [49, 48])
        #expect(ChatStore.remainingText(48) == "48 messages remaining today")
    }

    @Test func aFailedSendTakesTheMessageBackAndRestoresTheText() async {
        let (s, api) = make()
        s.input = "Hello"
        api.failNext = true
        let ok = await s.send()
        #expect(!ok)
        #expect(s.messages.isEmpty, "nothing was saved by the server, so nothing stays in the thread")
        #expect(s.input == "Hello")
        #expect(s.error == "Daily limit of 50 messages reached. Resets at midnight.")
        #expect(!s.sending)
    }

    @Test func emptyOrWaitingSendsNothing() async {
        let (s, api) = make()
        s.input = "   \n "
        #expect(await s.send() == false)
        #expect(api.calls.isEmpty)
        #expect(!s.canSend(aiEnabled: true))
        s.input = "x"
        #expect(s.canSend(aiEnabled: true) && !s.canSend(aiEnabled: false))
    }

    @Test func suggestionsFillTheBoxAndDoNotSend() async {
        let (s, api) = make()
        s.use(suggestion: ChatStore.suggestions[0])
        #expect(s.input == "What tasks are slipping this week?")
        #expect(api.calls.isEmpty && s.messages.isEmpty)
        #expect(ChatStore.suggestions.count == 4)
    }

    @Test func clearingEmptiesTheThread() async {
        let (s, api) = make([ChatMessage(role: "user", content: "hi")])
        await s.load()
        await s.clear()
        #expect(s.isEmpty && api.calls.last == "clear")
    }

    @Test func aFailedClearKeepsTheThreadAndSaysWhy() async {
        let (s, api) = make([ChatMessage(role: "user", content: "hi")])
        await s.load()
        api.failNext = true
        await s.clear()
        #expect(s.messages.count == 1 && s.error != nil)
    }

    @Test func aFailedLoadSaysWhy() async {
        let (s, api) = make()
        api.failNext = true
        await s.load()
        #expect(!s.loaded && s.error != nil)
        await s.load()
        #expect(s.loaded && s.error == nil)
    }
}
