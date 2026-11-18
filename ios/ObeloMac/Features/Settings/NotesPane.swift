import SwiftUI

/// Settings ▸ Notes: handwriting paper, autosave, and the note templates
struct NotesPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub

    @State private var editing: String?          // a template's id, or "new"
    @State private var draft = NoteTemplateDraft()
    @State private var deleting: NoteTemplate?

    private var notes: NoteSettingsStore { hub.notes }

    var body: some View {
        SettingsPage(notice: $hub.notes.notice) {
            if let p = notes.prefs {
                SettingsCard(title: "Handwriting paper", detail: "The paper behind handwritten notes. The pen colours adjust to it, and drawings made on one paper read fine on the other.") {
                    KitRadioGroup(options: NoteSettingsStore.papers.map { ($0.value, "\($0.label) — \($0.detail)") },
                                  selection: Binding(get: { p.notePaper ?? "theme" }, set: { hub.notes.setPaper($0) }), label: "Handwriting paper")
                }
                SettingsCard(title: "Autosave", detail: "Automatically save changes while editing a note") {
                    KitCheckbox(title: "Enable autosave", isOn: Binding(get: { p.autosaveEnabled }, set: { hub.notes.setAutosave(enabled: $0) }))
                    KitFieldLabel(text: "Save after") {
                        KitRadioGroup(options: NoteSettingsStore.autosaveChoices.map { ($0.value, "\($0.label) (\($0.detail))") },
                                      selection: Binding(get: { p.autosaveDuration }, set: { hub.notes.setAutosave(duration: $0) }), label: "Save after")
                            .disabled(!p.autosaveEnabled).opacity(p.autosaveEnabled ? 1 : 0.4)
                    }
                    Button("Save notes settings") {
                        Task { if await hub.notes.save() { app.me?.notePaper = hub.notes.prefs?.notePaper ?? "theme" } }
                    }
                    .buttonStyle(KitButtonStyle(.primary)).disabled(!notes.isDirty)
                }
            } else {
                KitEmptyState(message: "Loading…")
            }
            templates
        }
        .task {
            await hub.notes.load()
            await hub.templates.load()
        }
        .kitConfirm("Delete this template?", item: $deleting, confirmLabel: "Delete template", destructive: true) { t in
            Task { await hub.templates.remove(t.id) }
        }
    }

    // ── Templates ───────────────────────────────────────────────────────────

    private var templates: some View {
        SettingsCard(title: "Note templates",
                     detail: "Starting points for new notes (+ Note). They are yours to edit, delete and add to, and the same list shows on the web, iPhone, iPad and Mac. You can also save an open note as a template from the Notes screen.") {
            if let message = hub.templates.error { KitBanner(kind: .error, text: message) }
            if hub.templates.templates.isEmpty && hub.templates.loaded {
                Text("No templates. Add one below.").font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
            }
            ForEach(hub.templates.templates) { t in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.label).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                            Text((NoteTemplatesStore.typeLabels[t.type] ?? t.type) + (t.dateTitle ? " · dated title" : t.title.isEmpty ? "" : " · \(t.title)"))
                                .font(.system(size: 12)).foregroundStyle(theme.textMuted).lineLimit(1)
                        }
                        Spacer()
                        Button(editing == t.id ? "Close" : "Edit") { editing == t.id ? (editing = nil) : startEditing(t) }.buttonStyle(KitButtonStyle(.secondary, small: true))
                    }
                    if editing == t.id {
                        fields
                        HStack(spacing: 10) {
                            Button("Save template") { Task { if await hub.templates.update(t.id, draft) { editing = nil } } }.buttonStyle(KitButtonStyle(.primary))
                            Button("Delete template") { deleting = t }.buttonStyle(KitButtonStyle(.danger))
                        }
                    }
                }
                KitDivider()
            }
            if editing == "new" {
                Text("New template").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text200)
                fields
                HStack(spacing: 10) {
                    Button("Add template") { Task { if await hub.templates.create(draft) != nil { editing = nil } } }
                        .buttonStyle(KitButtonStyle(.primary)).disabled(hub.templates.atLimit)
                    Button("Cancel") { editing = nil }.buttonStyle(KitButtonStyle(.secondary))
                }
            } else {
                Button("New template") { draft = NoteTemplateDraft(); editing = "new" }.buttonStyle(KitButtonStyle(.secondary))
                    .disabled(hub.templates.atLimit)
            }
        }
    }

    private func startEditing(_ t: NoteTemplate) { draft = NoteTemplateDraft(t); editing = t.id }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            KitFieldLabel(text: "Name") { KitTextField(placeholder: "Standup", text: $draft.label) }
            KitFieldLabel(text: "Type") {
                KitSelect(options: NoteTemplatesStore.types.map { ($0, NoteTemplatesStore.typeLabels[$0] ?? $0) }, selection: $draft.type, label: "Type").frame(width: 180)
            }
            KitFieldLabel(text: "Starting title") { KitTextField(placeholder: "Standup — ", text: $draft.title) }
            KitCheckbox(title: "Use today's date as the title (the starting title above is then ignored)", isOn: $draft.dateTitle)
            KitFieldLabel(text: "Starting text (Markdown)") { KitTextArea(placeholder: "## Done\n- \n\n## Next\n- ", text: $draft.content, minHeight: 140) }
        }
    }
}

/// Settings ▸ Tags: rename or delete a tag everywhere, or make a new one
struct TagsPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var hub: SettingsHub
    @State private var newTag = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var deleting: SettingsTag?

    var body: some View {
        SettingsPage(notice: $hub.tags.notice) {
            SettingsCard(title: "Tag Manager",
                         detail: "Tags are shared across Notes, Tasks, Reminders, Routines, and Bookmarks. Renaming or deleting a tag updates every item that uses it.") {
                if hub.tags.loaded && hub.tags.tags.isEmpty {
                    Text("No tags yet. Add tags when creating or editing Notes, Tasks, Reminders, Routines, or Bookmarks.").font(.system(size: 14)).italic().foregroundStyle(theme.textMuted)
                }
                VStack(spacing: 0) {
                    ForEach(hub.tags.tags) { tag in
                        HStack(spacing: 10) {
                            if renaming == tag.name {
                                KitTextField(placeholder: tag.name, text: $renameText, onSubmit: { rename(tag) }, onCancel: { renaming = nil })
                                Button("Rename") { rename(tag) }.buttonStyle(KitButtonStyle(.primary, small: true))
                                Button("Cancel") { renaming = nil }.buttonStyle(KitButtonStyle(.secondary, small: true))
                            } else {
                                KitTagLabel(tag: tag.name)
                                Text("\(tag.count) item\(tag.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                                Spacer()
                                Button("Rename") { renaming = tag.name; renameText = tag.name }.buttonStyle(KitButtonStyle(.secondary, small: true))
                                Button("Delete") { deleting = tag }.buttonStyle(KitButtonStyle(.danger, small: true))
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { if tag.id != hub.tags.tags.last?.id { KitDivider() } }
                    }
                }
                KitDivider()
                Text("Create a new tag — it will appear as a suggestion in all modules:").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                HStack(spacing: 10) {
                    KitTextField(placeholder: "new-tag", text: $newTag, onSubmit: create)
                    Button("Create tag", action: create).buttonStyle(KitButtonStyle(.primary))
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .task { await hub.tags.load() }
        .kitConfirm(deleting.map(TagManagerStore.deleteQuestion) ?? "", item: $deleting, confirmLabel: "Delete", destructive: true) { tag in
            Task { if await hub.tags.delete(tag) { app.dataChanged() } }
        }
    }

    private func create() { Task { if await hub.tags.create(newTag) { newTag = "" } } }

    private func rename(_ tag: SettingsTag) {
        let text = renameText
        renaming = nil
        Task { if await hub.tags.rename(tag, to: text) { app.dataChanged() } }
    }
}
