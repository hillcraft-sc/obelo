import Foundation

/// What the server accepts as a note attachment (routes/notes.js: images, PDF or plain text, up to
/// 20 MB), so a file that would be refused is turned away before it is sent, with a plain message.
enum NoteAttachmentRules {
    static let maxBytes = 20 * 1024 * 1024

    private static let types: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
        "heic": "image/heic", "heif": "image/heif", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
        "pdf": "application/pdf", "txt": "text/plain", "text": "text/plain", "md": "text/plain", "log": "text/plain",
    ]

    enum Verdict: Equatable {
        case accepted(mimeType: String)
        case refused(String)
    }

    static func mimeType(forFilename name: String) -> String? {
        types[(name as NSString).pathExtension.lowercased()]
    }

    static func check(filename: String, byteCount: Int) -> Verdict {
        guard let mime = mimeType(forFilename: filename) else { return .refused("\u{201C}\(filename)\u{201D} isn't an image, PDF or text file.") }
        if byteCount > maxBytes { return .refused("\u{201C}\(filename)\u{201D} is over the 20 MB limit.") }
        if byteCount == 0 { return .refused("\u{201C}\(filename)\u{201D} is empty.") }
        return .accepted(mimeType: mime)
    }

    static func isImage(_ mimeType: String) -> Bool { mimeType.hasPrefix("image/") }

    /// The file's name, from the attachment's address (…/attachments/1731-photo.png)
    static func displayName(forURL url: String) -> String {
        guard let last = url.split(separator: "/").last else { return "File" }
        return String(last).removingPercentEncoding ?? String(last)
    }
}
