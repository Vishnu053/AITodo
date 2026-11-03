import SwiftUI
import AIToDoCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Todo?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if model.hasContent { HeadsUpSection() }

                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.todos) { todo in
                            TodoRow(todo: todo, onEdit: { editing = todo })
                        }
                    } header: {
                        Text(section.title).foregroundStyle(section.isOverdue ? Color.red : Color.secondary)
                    }
                }

                if !model.recentlyDone.isEmpty {
                    Section {
                        DisclosureGroup("Recently done (\(model.recentlyDone.count))") {
                            ForEach(model.recentlyDone) { done in TodoRow(todo: done, onEdit: { editing = done }) }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                if model.sections.isEmpty {
                    Text(model.hasAnyTodos
                         ? "All clear. Everything you finish stays in memory — type to recall it."
                         : "Nothing on your plate. Write a todo below — I’ll remember it.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.clear)
                        .padding(.top, 24)
                }
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Settings")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { CaptureBar() }
            .overlay(alignment: .bottom) { ToastView().padding(.bottom, 110) }
            .sheet(item: $editing) { todo in
                EditView(todo: todo, onSave: { model.save($0) }, onDelete: { model.delete(todo.id) })
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sensoryFeedback(.success, trigger: model.feedbackTick)
            .alert("Storage problem", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.storageError ?? "") }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<5: return "Still up?"
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Proactive section

struct HeadsUpSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Heads up") {
            if model.brief.loading {
                HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
            } else if !model.brief.message.isEmpty {
                Label(model.brief.message, systemImage: "sparkles")
            } else if model.aiAvailable {
                Button { Task { await model.loadBrief(force: true) } } label: { Label("Brief me", systemImage: "sparkles") }
            }
            ForEach(model.insights) { insight in
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.text).foregroundStyle(insight.kind == .overdue ? Color.red : Color.primary)
                    if !insight.actions.isEmpty {
                        HStack {
                            ForEach(insight.actions, id: \.self) { action in
                                Button(action.label) { model.run(action, on: insight) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Row

struct TodoRow: View {
    @Environment(AppModel.self) private var model
    let todo: Todo
    var onEdit: () -> Void

    var body: some View {
        let done = todo.done != nil
        HStack(alignment: .top, spacing: 12) {
            Button {
                done ? model.uncomplete(todo.id) : model.complete(todo.id)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark not done: \(todo.title)" : "Complete: \(todo.title)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if model.brief.focus.contains(todo.id) { Image(systemName: "star.fill").foregroundStyle(.tint).font(.caption) }
                    if todo.priority >= 2 { Text("!").foregroundStyle(.red).bold() }
                    Text(todo.title)
                        .fontWeight(todo.priority > 0 ? .semibold : .regular)
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                }
                meta
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions {
            Button(role: .destructive) { model.delete(todo.id) } label: { Label("Delete", systemImage: "trash") }
        }
        .listRowBackground(model.flashID == todo.id ? Color.yellow.opacity(0.25) : Color(.secondarySystemGroupedBackground))
        .animation(.default, value: model.flashID)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var meta: some View {
        let now = model.now, cal = model.store.calendar
        let late = Dates.isOverdue(todo, now: now, calendar: cal)
        let n = todo.completionDates.count
        let parts: [(String, Bool)] = [
            todo.due.map { (Dates.formatDue($0, allDay: todo.allDay, now: now, calendar: cal), late) },
            todo.repeatRule.map { ("↻ " + Dates.describeRepeat($0), false) },
            todo.tags.isEmpty ? nil : (todo.tags.map { "#\($0)" }.joined(separator: " "), false),
            todo.note.isEmpty ? nil : ("✎ note", false),
            n > 1 ? ("done \(n)×", false) : nil,
        ].compactMap { $0 }
        if !parts.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    Text(p.0).foregroundStyle(p.1 ? Color.red : Color.secondary).fontWeight(p.1 ? .semibold : .regular)
                }
            }
            .font(.caption)
        }
    }
}

// MARK: - Capture bar (live preview + recall)

struct CaptureBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 8) {
            if !model.recall.isEmpty { RecallCard() }
            if let p = model.preview { PreviewChips(parsed: p) }
            HStack(spacing: 8) {
                TextField("Write a todo, or type to recall…", text: $model.input)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { model.submit() }
                    .onChange(of: model.input) { model.inputChanged() }
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5))
                Button("Add") { model.submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

struct PreviewChips: View {
    @Environment(AppModel.self) private var model
    let parsed: ParsedTodo

    var body: some View {
        let chips = chipTexts
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { Text($0).font(.caption).padding(.horizontal, 10).padding(.vertical, 3).background(.thinMaterial, in: Capsule()) }
                    if let prior = model.priorHint {
                        Text("🧠 I’ll reuse details from “\(prior.title)”").font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 3).background(Color.yellow.opacity(0.25), in: Capsule())
                    }
                }
            }
        }
    }

    private var chipTexts: [String] {
        var c: [String] = []
        if let due = parsed.due { c.append("📅 " + Dates.formatDue(due, allDay: parsed.allDay, now: model.now, calendar: model.store.calendar)) }
        if let r = parsed.repeatRule { c.append("↻ " + Dates.describeRepeat(r)) }
        if parsed.priority > 0 { c.append(String(repeating: "!", count: parsed.priority)) }
        c += parsed.tags.map { "#\($0)" }
        return c
    }
}

struct RecallCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FROM YOUR MEMORY").font(.caption2).bold().foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
            ForEach(Array(model.recall.enumerated()), id: \.element.todo.id) { i, hit in
                if i > 0 { Divider() }
                row(hit.todo)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5))
    }

    private func row(_ t: Todo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).lineLimit(1)
                Text(line(t)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(t.status == .open ? "Show" : t.status == .deleted ? "Restore" : "Add again") {
                t.status == .open ? model.show(t.id) : model.readd(t.id)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func line(_ t: Todo) -> String {
        let d = { (date: Date) in date.formatted(.dateTime.month(.abbreviated).day().year()) }
        var s: String
        switch t.status {
        case .open: s = "On your list" + (t.due.map { " · " + Dates.formatDue($0, allDay: t.allDay, now: model.now, calendar: model.store.calendar) } ?? "")
        case .done:
            let n = t.completionDates.count
            s = "Done " + (n > 1 ? "\(n)× · last " : "") + (t.completionDates.last.map(d) ?? "")
        case .deleted: s = "Deleted " + (t.deleted.map(d) ?? "")
        }
        if !t.note.isEmpty { s += " · " + t.note.prefix(60) }
        return s
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 14) {
                Text(toast.message).font(.subheadline)
                if let label = toast.actionLabel, let action = toast.action {
                    Button(label) { action(); model.toast = nil }.font(.subheadline.bold())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8, y: 2)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
