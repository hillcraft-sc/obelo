import SwiftUI

// tasks/show.ejs: title, meta row (status, priority, due, recurrence), tags, notes, subtasks.

struct TaskDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let id: Int

    @State private var task: TaskItem?
    @State private var error: String?
    @State private var newSubtask = ""
    @State private var editing = false
    @State private var confirmDelete = false

    struct R: Decodable { let task: TaskItem }

    var body: some View {
        Loadable(value: task, error: error, retry: load) { task in
            Page(refresh: load) {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(task.title).font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textPrimary)
                        meta(task)
                        if !task.tags.isEmpty {
                            FlowLayout(spacing: 6) { ForEach(task.tags, id: \.self) { TagPill(tag: $0) } }
                        }
                        if !task.notes.isEmpty {
                            RowDivider()
                            MarkdownView(text: task.notes)
                        }
                    }
                }
                subtasks(task)
                actions(task)
            }
        }
        .themedNavBar(theme, title: "Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }.disabled(task == nil)
            }
        }
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let task { TaskForm(task: task, defaultStatus: task.status) { _ in Task { await load(); app.dataChanged() } } }
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
    }

    private func meta(_ task: TaskItem) -> some View {
        FlowLayout(spacing: 12) {
            StatusMenu(status: task.status) { s in
                toast.run {
                    let r: R = try await APIClient.shared.post("/tasks/\(id)", ["status": s], method: "PATCH")
                    self.task?.status = r.task.status
                    app.dataChanged()
                }
            }
            if task.priority != "none" {
                HStack(spacing: 6) {
                    Dot(color: theme.priorityDot(task.priority))
                    Text("\(Fmt.priorityLabel(task.priority)) priority").font(.system(size: 14)).foregroundStyle(theme.text400)
                }
            }
            if task.dueDate != nil || task.dueTime != nil {
                Label(Fmt.due(task.dueDate, task.dueTime, hour12: app.hour12), systemImage: "calendar")
                    .font(.system(size: 14))
                    .foregroundStyle(task.dueState == "overdue" ? theme.red400 : task.dueState == "today" ? theme.green400 : theme.text400)
            }
            if task.recurring {
                Label(Fmt.recurLabel(task.recurRule), systemImage: "repeat").font(.system(size: 14)).foregroundStyle(theme.text400)
            }
        }
    }

    private func subtasks(_ task: TaskItem) -> some View {
        let subs = task.subtasks ?? []
        let done = subs.filter(\.done).count
        return Card {
            CardHeader(title: "Subtasks", note: subs.isEmpty ? nil : "\(done)/\(subs.count)")
            ForEach(subs) { sub in
                HStack(spacing: 12) {
                    CompleteCircle(done: sub.done) { toggle(sub) }
                    Text(sub.title).font(.system(size: 14))
                        .strikethrough(sub.done, color: theme.textMuted)
                        .foregroundStyle(sub.done ? theme.textMuted : theme.text200)
                    Spacer()
                    Button { removeSub(sub) } label: {
                        Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 11)
                RowDivider()
            }
            HStack(spacing: 8) {
                ThemedField(placeholder: "Add a subtask…", text: $newSubtask) { addSub() }
                SecondaryButton(title: "Add") { addSub() }
            }
            .padding(16)
        }
    }

    private func actions(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            if task.isDone {
                SecondaryButton(title: "Restore", systemImage: "arrow.uturn.backward") {
                    toast.run {
                        try await APIClient.shared.post("/tasks/\(id)/restore")
                        await load(); app.dataChanged()
                    }
                }
            } else {
                PrimaryButton(title: "Mark complete", systemImage: "checkmark") {
                    toast.run {
                        try await APIClient.shared.post("/tasks/\(id)/complete")
                        app.dataChanged()
                        dismiss()
                    }
                }
            }
            Spacer()
            SecondaryButton(title: "Delete", systemImage: "trash", tint: theme.red400) { confirmDelete = true }
        }
    }

    private func load() async {
        do {
            let r: R = try await APIClient.shared.get("/tasks/\(id)")
            task = r.task
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addSub() {
        let title = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newSubtask = ""
        toast.run {
            try await APIClient.shared.post("/tasks/\(id)/subtasks", ["title": title])
            await load()
        }
    }

    private func toggle(_ sub: TaskItem.Subtask) {
        toast.run {
            try await APIClient.shared.post("/tasks/\(id)/subtasks/\(sub.id)/toggle")
            await load()
        }
    }

    private func removeSub(_ sub: TaskItem.Subtask) {
        toast.run {
            try await APIClient.shared.delete("/tasks/\(id)/subtasks/\(sub.id)")
            await load()
        }
    }

    private func delete() {
        toast.run {
            try await APIClient.shared.delete("/tasks/\(id)")
            app.dataChanged()
            dismiss()
        }
    }
}

/// tasks/form.ejs — create or edit
struct TaskForm: View {
    @Environment(\.theme) private var theme
    let task: TaskItem?
    var defaultStatus = "inbox"
    let saved: (TaskItem) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var status = "inbox"
    @State private var priority = "none"
    @State private var dueDate: String?
    @State private var dueTime: String?
    @State private var tags: [String] = []
    @State private var recurring = false
    @State private var recurRule = "daily"
    @State private var allTags: [String] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FormSheet(title: task == nil ? "New Task" : "Edit Task", saveTitle: task == nil ? "Create" : "Save",
                  canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, error: error, save: save) {
            FormSection(label: "Title") { ThemedField(placeholder: "What needs doing?", text: $title) }
            FormSection(label: "Notes") { ThemedField(placeholder: "Markdown supported", text: $notes, axis: .vertical).lineLimit(4...12) }
            HStack(spacing: 12) {
                FormSection(label: "Status") {
                    SelectField(options: Fmt.statuses.map { ($0, Fmt.statusLabels[$0] ?? $0) }, selection: $status)
                }
                FormSection(label: "Priority") {
                    SelectField(options: Fmt.priorities.map { ($0, Fmt.priorityLabel($0)) }, selection: $priority)
                }
            }
            FormSection(label: "Due date") { OptionalDateField(ymd: $dueDate) }
            FormSection(label: "Due time") { OptionalTimeField(hhmm: $dueTime) }
            FormSection(label: "Tags") { TagsField(tags: $tags, suggestions: allTags) }
            ToggleRow(title: "Recurring", subtitle: "Creates the next one when you complete this", isOn: $recurring)
            if recurring {
                SelectField(options: Fmt.recurRules, selection: $recurRule)
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let task {
                title = task.title; notes = task.notes; status = task.status; priority = task.priority
                dueDate = task.dueDate; dueTime = task.dueTime; tags = task.tags
                recurring = task.recurring; recurRule = task.recurRule ?? "daily"
            } else {
                status = defaultStatus
            }
            struct T: Decodable { let tags: [String] }
            allTags = ((try? await APIClient.shared.get("/tags")) as T?)?.tags ?? []
        }
    }

    private func save() async -> Bool {
        let body: [String: Any] = [
            "title": title, "notes": notes, "status": status, "priority": priority,
            "dueDate": dueDate ?? NSNull(), "dueTime": dueTime ?? NSNull(), "tags": tags,
            "recurring": recurring, "recurRule": recurRule,
        ]
        do {
            struct R: Decodable { let task: TaskItem }
            let r: R = if let task {
                try await APIClient.shared.post("/tasks/\(task.id)", body, method: "PATCH")
            } else {
                try await APIClient.shared.post("/tasks", body)
            }
            saved(r.task)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
