import Testing
@testable import ObeloShared

struct ServerVersionTests {
    @Test func olderServersAreFlagged() {
        #expect(ServerVersion.isOlder("3.54.0", than: "3.55.0"))
        #expect(ServerVersion.isOlder("3.9.9", than: "3.10.0"))
        #expect(ServerVersion.isOlder("2.99.99", than: "3.0.0"))
    }

    @Test func sameOrNewerServersAreNotFlagged() {
        #expect(!ServerVersion.isOlder("3.55.0", than: "3.55.0"))
        #expect(!ServerVersion.isOlder("3.55.1", than: "3.55.0"))
        #expect(!ServerVersion.isOlder("3.100.0", than: "3.55.0"))
        #expect(!ServerVersion.isOlder("3.55", than: "3.55.0"))
    }

    @Test func aMissingVersionIsNotTreatedAsOld() {
        #expect(!ServerVersion.isOlder(nil))
        #expect(ServerVersion.notice(server: nil) == nil)
    }

    @Test func noticeNamesBothVersions() {
        let text = ServerVersion.notice(server: "3.54.0")
        #expect(text?.contains("3.54.0") == true)
        #expect(text?.contains(ServerVersion.needed) == true)
    }
}
