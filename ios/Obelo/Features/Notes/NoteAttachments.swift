import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

// A note's attachments (notes/show.ejs "Attachments"): photo grid, other files as rows, and
// adding photos from the library or camera. Photos are resized to at most 2560px and sent as
// JPEG, which keeps uploads well under the server's 20 MB limit.

struct NoteAttachmentsCard: View {
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    let noteID: Int
    @Binding var attachments: [Note.Attachment]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var uploading = 0
    @State private var viewing: Note.Attachment?

    private var images: [Note.Attachment] { attachments.filter { $0.mimeType.hasPrefix("image/") } }
    private var files: [Note.Attachment] { attachments.filter { !$0.mimeType.hasPrefix("image/") } }

    var body: some View {
        Card {
            CardHeader(title: "Attachments", badge: attachments.isEmpty ? nil : "\(attachments.count)") {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { showLibrary = true }
                    #if os(iOS)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo", systemImage: "camera") { showCamera = true }
                    }
                    #endif
                } label: {
                    Label("Add photo", systemImage: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accentText)
                }
            }
            if attachments.isEmpty && uploading == 0 {
                Text("No attachments yet.").font(.system(size: 13)).italic().foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 20).padding(.vertical, 14)
            }
            if !images.isEmpty || uploading > 0 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(images) { a in
                        Button { viewing = a } label: {
                            AttachmentImage(path: a.url)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo")
                    }
                    ForEach(0..<uploading, id: \.self) { _ in
                        ZStack { theme.elevated; ProgressView() }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
            ForEach(files) { a in
                RowDivider()
                HStack(spacing: 12) {
                    Image(systemName: a.mimeType == "application/pdf" ? "doc.richtext" : "doc.text").foregroundStyle(theme.accentText)
                    Text(a.url.split(separator: "/").last.map { String($0).removingPercentEncoding ?? String($0) } ?? "File")
                        .font(.system(size: 13)).foregroundStyle(theme.text300).lineLimit(1)
                    Spacer()
                    Button { delete(a) } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(theme.textMuted) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await uploadPicked(items) }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await upload([image]) } }.ignoresSafeArea()
        }
        #endif
        .fullScreen(item: $viewing) { a in
            PhotoViewer(path: a.url) { delete(a); viewing = nil }
        }
    }

    private func uploadPicked(_ items: [PhotosPickerItem]) async {
        var images: [PlatformImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = PlatformImage(data: data) { images.append(image) }
        }
        await upload(images)
    }

    private func upload(_ images: [PlatformImage]) async {
        uploading += images.count
        var added = 0
        for image in images {
            defer { uploading -= 1 }
            guard let jpeg = Self.jpeg(image) else { continue }
            do {
                struct R: Decodable { let attachment: Note.Attachment }
                let r: R = try await APIClient.shared.upload("/notes/\(noteID)/attachments", field: "photo", data: jpeg,
                                                            filename: "photo-\(Int(Date.now.timeIntervalSince1970)).jpg", mimeType: "image/jpeg")
                withAnimation { attachments.append(r.attachment) }
                added += 1
            } catch {
                toast.show(error.localizedDescription, error: true)
            }
        }
        if added > 0 { toast.show(added == 1 ? "Photo added" : "\(added) photos added") }
    }

    private func delete(_ a: Note.Attachment) {
        withAnimation { attachments.removeAll { $0.id == a.id } }
        toast.run { try await APIClient.shared.delete("/notes/\(noteID)/attachments/\(a.id)") }
    }

    /// Downscale to at most 2560px on the long side and encode as JPEG
    static func jpeg(_ image: PlatformImage, maxSide: CGFloat = 2560) -> Data? {
        image.jpegData(maxSide: maxSide, quality: 0.85)
    }
}

/// Full-screen photo with pinch to zoom, share and delete
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let path: String
    let delete: () -> Void
    @State private var image: PlatformImage?
    @State private var scale: CGFloat = 1
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(platformImage: image).resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, $0.magnification)) }.onEnded { _ in
                        if scale < 1.1 { withAnimation { scale = 1 } }
                    })
                    .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                if let image {
                    ShareLink(item: Image(platformImage: image), preview: SharePreview("Photo", image: Image(platformImage: image))) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.white.opacity(0.15), in: Circle())
                    }
                }
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Delete photo")
            }
            .padding(.horizontal, 16)
        }
        .confirmationDialog("Delete this photo from the note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
        .task {
            if let data = try? await APIClient.shared.data(path: path) { image = PlatformImage(data: data) }
        }
    }
}

#if os(iOS)
/// UIKit camera, since SwiftUI has no camera picker
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let picked: (PlatformImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? PlatformImage { parent.picked(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif
