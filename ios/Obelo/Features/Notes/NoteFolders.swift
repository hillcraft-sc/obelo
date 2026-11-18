import SwiftUI

// Note folders — the web workspace's folder tree (views/notes/workspace.ejs). On iPhone the tree is a
// drawer (a sheet) from the Notes header, and the notes list shows the open folder's subfolders as rows
// you can open or drop a note on.

/// The folder drawer: All notes, Top level, and the folder tree. Long-press a folder to add a
/// subfolder, rename it or delete it.
struct FoldersSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Toast.self) private var toast
    @Binding var folders: [NoteFolder]
    @Binding var scope: NoteScope
    /// Note count per folder id (0 = the top level), from the notes the list has loaded
    let counts: [Int: Int]
    let total: Int

    @State private var naming: Naming?
    @State private var name = ""
    @State private var deleting: NoteFolder?

    enum Naming: Identifiable {
        case new(parent: Int?), rename(NoteFolder)
        var id: String {
            switch self {
            case .new(let p): "new\(p ?? 0)"
            case .rename(let f): "rename\(f.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 2) {
                    row(icon: "tray.full", title: "All notes", count: total, depth: 0, selected: scope == .all) { pick(.all) }
                    row(icon: "doc.text", title: "Top level", count: counts[0] ?? 0, depth: 0, selected: scope == .folder(nil)) { pick(.folder(nil)) }
                    if !folders.isEmpty {
                        Text("FOLDERS").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                    }
                    ForEach(NoteFolders.tree(folders), id: \.folder.id) { item in
                        row(icon: "folder", title: item.folder.name, count: counts[item.folder.id] ?? 0, depth: item.depth,
                            selected: scope == .folder(item.folder.id)) { pick(.folder(item.folder.id)) }
                            .contextMenu {
                                Button { startNaming(.new(parent: item.folder.id)) } label: { Label("New subfolder", systemImage: "folder.badge.plus") }
                                Button { startNaming(.rename(item.folder)) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = item.folder } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if folders.isEmpty {
                        Text("No folders yet. Folders keep related notes together.")
                            .font(.system(size: 13)).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 20)
                    } else {
                        Text("Long-press a folder to add a subfolder, rename it or delete it.")
                            .font(.system(size: 12)).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 12)
                    }
                }
                .padding(12)
            }
            .background(theme.page)
            .themedNavBar(theme, title: "Folders")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { startNaming(.new(parent: nil)) } label: { Label("New folder", systemImage: "folder.badge.plus") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.text400)
                }
            }
            .alert(naming.map { if case .rename = $0 { "Rename folder" } else { "New folder" } } ?? "",
                   isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Folder name", text: $name)
                Button("Cancel", role: .cancel) { naming = nil }
                Button("Save") { saveName() }
            }
            .confirmationDialog("Delete \(deleting?.name ?? "folder")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete folder", role: .destructive) { deleteFolder() }
            } message: {
                Text("Its notes and subfolders move up one level. No notes are deleted.")
            }
        }
        .presentationBackground(theme.page)
    }

    private func row(icon: String, title: String, count: Int, depth: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? icon + ".fill" : icon).font(.system(size: 15))
                    .foregroundStyle(selected ? theme.accentText : theme.textMuted).frame(width: 22)
                Text(title).font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? theme.textPrimary : theme.text200).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").font(.system(size: 12)).foregroundStyle(theme.textMuted) }
            }
            .padding(.leading, 12 + CGFloat(depth) * 20).padding(.trailing, 12).padding(.vertical, 11)
            .background(selected ? theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ s: NoteScope) {
        scope = s
        dismiss()
    }

    private func startNaming(_ n: Naming) {
        if case .rename(let f) = n { name = f.name } else { name = "" }
        naming = n
    }

    private func saveName() {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = naming, !text.isEmpty else { naming = nil; return }
        naming = nil
        toast.run {
            switch n {
            case .new(let parent):
                let _: NoteFolders.One = try await APIClient.shared.post("/folders", ["name": text, "parentId": parent.map { $0 as Any } ?? NSNull()])
            case .rename(let f):
                let _: NoteFolders.One = try await APIClient.shared.post("/folders/\(f.id)", ["name": text], method: "PATCH")
            }
            folders = try await NoteFolders.load()
        }
    }

    private func deleteFolder() {
        guard let f = deleting else { return }
        deleting = nil
        toast.run {
            try await APIClient.shared.delete("/folders/\(f.id)")
            // The open folder went away: show its parent
            if scope == .folder(f.id) { scope = .folder(f.parentId) }
            folders = try await NoteFolders.load()
            toast.show("Folder deleted")
        }
    }
}

/// "Move to…": pick a folder for a note
struct MoveToFolderSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let folders: [NoteFolder]
    let current: Int?
    let move: (Int?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 2) {
                    option(nil, title: "Top level", icon: "doc.text", depth: 0)
                    ForEach(NoteFolders.tree(folders), id: \.folder.id) { item in
                        option(item.folder.id, title: item.folder.name, icon: "folder", depth: item.depth)
                    }
                    if folders.isEmpty {
                        Text("No folders yet. Open Folders on the Notes page to add one.")
                            .font(.system(size: 13)).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 20)
                    }
                }
                .padding(12)
            }
            .background(theme.page)
            .themedNavBar(theme, title: "Move to")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(theme.text400) }
            }
        }
        .presentationBackground(theme.page)
    }

    private func option(_ id: Int?, title: String, icon: String, depth: Int) -> some View {
        Button {
            if id != current { move(id) }
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(theme.textMuted).frame(width: 22)
                Text(title).font(.system(size: 15)).foregroundStyle(theme.text200).lineLimit(1)
                Spacer()
                if id == current { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accentText) }
            }
            .padding(.leading, 12 + CGFloat(depth) * 20).padding(.trailing, 12).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A subfolder row in the notes list. Tap to open it; drop a note on it to move the note there.
struct FolderRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var icon = "folder"
    var count = 0
    let open: () -> Void
    let drop: (Int) -> Void
    @State private var targeted = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: targeted ? icon + ".fill" : icon).font(.system(size: 15))
                    .foregroundStyle(targeted ? theme.accentText : theme.textMuted).frame(width: 22)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").font(.system(size: 12)).foregroundStyle(theme.textMuted) }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(targeted ? theme.accent.opacity(0.18) : theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(targeted ? theme.accent : theme.border1, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(NoteFolders.noteID(fromDrag:)).first else { return false }
            drop(id)
            return true
        } isTargeted: { targeted = $0 }
        .accessibilityHint("Opens the folder. Drop a note here to move it.")
    }
}
