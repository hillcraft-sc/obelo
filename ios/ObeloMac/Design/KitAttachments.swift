import AppKit
import SwiftUI

// Attachments (web: the Attachments block in notes/workspace.ejs): thumbnails, file rows, the picture
// viewer, and the drop area for files dragged from Finder. The files are behind the sign-in, so images
// are fetched with the app's session.

/// Fetches and remembers attachment pictures
@MainActor
final class KitImageLoader {
    static let shared = KitImageLoader()
    private let cache = NSCache<NSString, NSImage>()

    /// Puts a picture in the cache (the preview's sample attachments)
    func preload(path: String, image: NSImage) { cache.setObject(image, forKey: path as NSString) }

    func image(path: String) async -> NSImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        guard let data = try? await APIClient.shared.data(path: path), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

/// A square picture of an attached image. Click opens it larger (`onOpen`).
struct KitAttachmentThumb: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @State private var image: NSImage?
    @State private var failed = false
    let path: String
    let name: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                theme.elevated
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(theme.textMuted).accessibilityLabel("Picture could not be loaded")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(hovering ? theme.accent : theme.border1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
        .accessibilityLabel("Photo \(name)")
        .task(id: path) {
            image = await KitImageLoader.shared.image(path: path)
            failed = image == nil
        }
    }
}

/// A file that isn't a picture: an icon and its name; click opens it
struct KitAttachmentFileRow: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let name: String
    let mimeType: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: mimeType == "application/pdf" ? "doc.richtext" : "doc.text").foregroundStyle(theme.accentText).accessibilityHidden(true)
                Text(name).font(.system(size: 13)).foregroundStyle(hovering ? theme.text100 : theme.text300).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(hovering ? theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(name)")
        .accessibilityLabel("File \(name)")
    }
}

/// An image shown larger, over the window. Escape or Close dismisses it.
struct KitImageViewer: View {
    @Environment(\.theme) private var theme
    @State private var image: NSImage?
    let path: String
    let name: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text200).lineLimit(1)
                Spacer()
                Button("Close", action: onClose).buttonStyle(KitButtonStyle(.secondary, small: true)).keyboardShortcut(.cancelAction)
            }
            .padding(12)
            KitDivider()
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(16)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, idealWidth: 760, minHeight: 420, idealHeight: 600)
        .background(theme.surface)
        .task(id: path) { image = await KitImageLoader.shared.image(path: path) }
    }
}

extension View {
    /// Accepts files dragged from Finder. While they are over the view it shows a dashed accent frame
    /// and `message`.
    func kitFileDrop(message: String = "Drop to attach", isTargeted: Binding<Bool>, perform: @escaping ([URL]) -> Void) -> some View {
        modifier(KitFileDrop(message: message, isTargeted: isTargeted, perform: perform))
    }
}

private struct KitFileDrop: ViewModifier {
    @Environment(\.theme) private var theme
    let message: String
    @Binding var isTargeted: Bool
    let perform: ([URL]) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                perform(files)
                return true
            } isTargeted: { isTargeted = $0 }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(Text(message).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.accentText))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
    }
}
