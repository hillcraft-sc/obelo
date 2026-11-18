import Testing
@testable import ObeloShared

@Suite struct NoteAttachmentRulesTests {
    @Test func imagesPdfAndTextAreAccepted() {
        #expect(NoteAttachmentRules.check(filename: "scan.PNG", byteCount: 1000) == .accepted(mimeType: "image/png"))
        #expect(NoteAttachmentRules.check(filename: "a.jpeg", byteCount: 1000) == .accepted(mimeType: "image/jpeg"))
        #expect(NoteAttachmentRules.check(filename: "plan.pdf", byteCount: 1000) == .accepted(mimeType: "application/pdf"))
        #expect(NoteAttachmentRules.check(filename: "todo.txt", byteCount: 10) == .accepted(mimeType: "text/plain"))
        #expect(NoteAttachmentRules.check(filename: "notes.md", byteCount: 10) == .accepted(mimeType: "text/plain"))
    }

    @Test func otherFilesAreTurnedAwayWithAPlainMessage() {
        #expect(NoteAttachmentRules.check(filename: "app.zip", byteCount: 10) == .refused("\u{201C}app.zip\u{201D} isn't an image, PDF or text file."))
        #expect(NoteAttachmentRules.check(filename: "noextension", byteCount: 10) == .refused("\u{201C}noextension\u{201D} isn't an image, PDF or text file."))
    }

    @Test func theTwentyMegabyteLimitIsKept() {
        #expect(NoteAttachmentRules.check(filename: "a.png", byteCount: NoteAttachmentRules.maxBytes) == .accepted(mimeType: "image/png"))
        #expect(NoteAttachmentRules.check(filename: "a.png", byteCount: NoteAttachmentRules.maxBytes + 1) == .refused("\u{201C}a.png\u{201D} is over the 20 MB limit."))
        #expect(NoteAttachmentRules.check(filename: "a.png", byteCount: 0) == .refused("\u{201C}a.png\u{201D} is empty."))
    }

    @Test func theNameComesFromTheAddress() {
        #expect(NoteAttachmentRules.displayName(forURL: "/notes/4/attachments/1731-my%20photo.png") == "1731-my photo.png")
        #expect(NoteAttachmentRules.isImage("image/heic"))
        #expect(!NoteAttachmentRules.isImage("application/pdf"))
    }
}
