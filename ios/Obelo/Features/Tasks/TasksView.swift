import SwiftUI

// Tasks — views/tasks/index.ejs: view tabs with badges, search, tag filter, quick-add, and
// the task list card (grouped by day in Upcoming).

struct TasksView: View {
    @Environment(AppState.self) private var app
    @Environment(Toast.self) private var toast
    @Environment(\.theme) private var theme

    struct Response: Decodable {
        let tasks: [TaskItem]
        let tags: [String]
        let counts: Counts
        struct Counts: Decodable { let today: Int; let inbox: Int; let slipping: Int }
    }

    @State private var view = "inbox"
    @State private var tag: String?
    @State private var search = ""
    @State private var quickAdd = ""
    @State private var data: Response?
    @State private var tasks: [TaskItem] = []
    @State private var error: String?
    @State private var showNew = false

    var body: some View {
        Page(refresh: load) {
            PageHeader(title: "Tasks", subtitle: "Everything you plan to do, from inbox to done.", pageName: true) {
                PrimaryButton(title: "New task", systemImage: "plus") { showNew = true }
            }
            SectionTabs(tabs: [
                SectionTab(key: "inbox", label: "Inbox", badge: data?.counts.inbox),
                SectionTab(key: "today", label: "Today", badge: data?.counts.today),
                SectionTab(key: "upcoming", label: "Upcoming"),
                SectionTab(key: "all", label: "All"),
                SectionTab(key: "completed", label: "Completed"),
                SectionTab(key: "archived", label: "Archived"),
                SectionTab(key: "slipping", label: "Slipping", badge: data?.counts.slipping, warn: true),
            ], selection: $view)

            ThemedField(placeholder: "Search tasks...", text: $search) { Task { await load() } }
                .submitLabel(.search)
            TagFilter(tags: data?.tags ?? [], selected: $tag)

            if !["completed", "slipping", "archived"].contains(view) {
                HStack(spacing: 8) {
                    ThemedField(placeholder: "Quick-add a task and press Enter...", text: $quickAdd) { add() }
                    SecondaryButton(title: "Add") { add() }
                }
            }
            if view == "slipping" && !tasks.isEmpty {
                Banner(kind: .warning, text: "These tasks haven't been updated in 7 days. Give them some attention or archive them.")
            }
            if let error { Banner(kind: .error, text: error) }

            Card { list }
        }
        .task(id: "\(view)|\(tag ?? "")|\(app.dataVersion)") { await load() }
        #if DEBUG
        // Simulator testing: `-tasksView <view>` and `-tasksSearch <text>` open Tasks on that view or search
        .onAppear {
            let d = UserDefaults.standard
            if let v = d.string(forKey: "tasksView") { view = v }
            if let q = d.string(forKey: "tasksSearch"), search.isEmpty { search = q }
        }
        #endif
        .onChange(of: search) { _, new in if new.isEmpty { Task { await load() } } }
        .onNewItem("tasks") { showNew = true }
        .sheet(isPresented: $showNew) {
            TaskForm(task: nil, defaultStatus: view == "today" ? "today" : "inbox") { _ in Task { await load() } }
        }
    }

    @ViewBuilder private var list: some View {
        if data == nil {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        } else if tasks.isEmpty {
            EmptyRow(text: emptyText, action: emptyAction)
        } else if view == "upcoming" {
            let groups = Dictionary(grouping: tasks) { $0.dueDate ?? "" }
            ForEach(groups.keys.sorted(), id: \.self) { day in
                GroupLabel(title: day.isEmpty ? "No date" : Fmt.weekdayShort(day))
                rows(groups[day] ?? [])
            }
        } else {
            rows(tasks)
        }
    }

    private func rows(_ items: [TaskItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { i, task in
            if i > 0 { RowDivider() }
            SwipeRow(onComplete: task.isDone ? nil : { complete(task) }, onDelete: task.isDone ? nil : { delete(task) }) {
                TaskRow(task: task, hour12: app.hour12) { complete(task) } restore: { restore(task) } setStatus: { setStatus(task, $0) }
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    private var filtered: Bool { tag != nil || !search.isEmpty }

    /// Same wording as views/tasks/index.ejs
    private var emptyText: String {
        if filtered { return "No tasks match this filter." }
        return switch view {
        case "inbox": "No inbox tasks yet."
        case "today": "Nothing due today."
        case "upcoming": "Nothing due in the next 7 days."
        case "completed": "No completed tasks yet."
        case "archived": "No archived tasks yet."
        case "slipping": "No slipping tasks."
        default: "No tasks yet."
        }
    }

    private var emptyAction: EmptyAction? {
        if filtered { return EmptyAction(label: "Clear filter") { tag = nil; search = "" } }
        return ["completed", "archived", "slipping"].contains(view) ? nil : EmptyAction(label: "New task") { showNew = true }
    }

    // ── Data ─────────────────────────────────────────────────────────────────

    private func load() async {
        do {
            let r: Response = try await APIClient.shared.get("/tasks", query: ["view": view, "tag": tag, "search": search.isEmpty ? nil : search])
            data = r
            withAnimation(.easeOut(duration: 0.15)) { tasks = r.tasks }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add() {
        let title = quickAdd.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        quickAdd = ""
        toast.run {
            struct R: Decodable { let task: TaskItem }
            let r: R = try await APIClient.shared.post("/tasks", ["title": title, "status": view == "today" ? "today" : "inbox"])
            withAnimation { tasks.insert(r.task, at: 0) }
            app.dataChanged()
        }
    }

    private func complete(_ task: TaskItem) {
        withAnimation(.easeOut(duration: 0.25)) { tasks.removeAll { $0.id == task.id } }
        toast.run {
            try await APIClient.shared.post("/tasks/\(task.id)/complete")
            app.dataChanged()
        }
    }

    private func restore(_ task: TaskItem) {
        withAnimation(.easeOut(duration: 0.25)) { tasks.removeAll { $0.id == task.id } }
        toast.run {
            try await APIClient.shared.post("/tasks/\(task.id)/restore")
            app.dataChanged()
        }
    }

    private func delete(_ task: TaskItem) {
        withAnimation(.easeOut(duration: 0.25)) { tasks.removeAll { $0.id == task.id } }
        toast.run {
            try await APIClient.shared.delete("/tasks/\(task.id)")
            toast.show("Task deleted")
            app.dataChanged()
        }
    }

    private func setStatus(_ task: TaskItem, _ status: String) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].status = status }
        toast.run {
            try await APIClient.shared.post("/tasks/\(task.id)", ["status": status], method: "PATCH")
            app.dataChanged()
        }
    }
}

/// tasks/_row.ejs
struct TaskRow: View {
    @Environment(\.theme) private var theme
    let task: TaskItem
    let hour12: Bool
    let complete: () -> Void
    let restore: () -> Void
    let setStatus: (String) -> Void

    private var dueColor: Color {
        switch task.dueState {
        case "overdue": theme.red400
        case "today": theme.green400
        default: theme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CompleteCircle(done: task.isDone) { task.isDone ? restore() : complete() }
            PriorityIcon(priority: task.priority)
            NavigationLink(value: Route.task(task.id)) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.system(size: 14))
                        .strikethrough(task.isDone, color: theme.textMuted)
                        .foregroundStyle(task.isDone ? theme.textMuted : theme.text200)
                        .lineLimit(1)
                    if task.recurring {
                        Image(systemName: "repeat").font(.system(size: 10)).foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 0)
                    if task.dueDate != nil {
                        Text(Fmt.shortDay(task.dueDate)).font(.system(size: 12)).foregroundStyle(dueColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            StatusMenu(status: task.status, onChange: setStatus)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// The inline status <select> (statusSelectHtml in routes/tasks.js)
struct StatusMenu: View {
    @Environment(\.theme) private var theme
    let status: String
    let onChange: (String) -> Void

    static func color(_ status: String, _ theme: Theme) -> Color {
        switch status {
        case "today": theme.accentText
        case "in-progress": theme.amber400
        case "done": theme.green400
        case "archived": theme.textMuted
        default: theme.text400
        }
    }

    var body: some View {
        Menu {
            ForEach(Fmt.statuses, id: \.self) { s in
                Button {
                    onChange(s)
                } label: {
                    if s == status { Label(Fmt.statusLabels[s] ?? s, systemImage: "checkmark") } else { Text(Fmt.statusLabels[s] ?? s) }
                }
            }
        } label: {
            Text(Fmt.statusLabels[status] ?? status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Self.color(status, theme))
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
