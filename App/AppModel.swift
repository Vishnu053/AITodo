import Foundation
import Observation
import AIToDoCore

struct Toast: Identifiable {
    let id = UUID()
    var message: String
    var actionLabel: String?
    var action: (() -> Void)?
}

struct TodoSection: Identifiable {
    var id: String { title }
    var title: String
    var isOverdue = false
    var todos: [Todo]
}

struct BriefState: Equatable {
    var message = ""
    var focus: [UUID] = []
    var loading = false
}

@MainActor
@Observable
final class AppModel {
    // MARK: State the views read
    private(set) var items: [Todo] = []
    var input = ""
    private(set) var recall: [RecallHit] = []
    private(set) var preview: ParsedTodo?
    private(set) var priorHint: Todo?
    private(set) var brief = BriefState()
    private(set) var aiEnabled: Bool
    private(set) var remindersEnabled: Bool
    var flashID: UUID?
    var toast: Toast?
    var storageError: String?
    private(set) var feedbackTick = 0

    // MARK: Collaborators
    @ObservationIgnored let store: TodoStore
    @ObservationIgnored let assistant: any TodoAssistant
    @ObservationIgnored private let reminders = Reminders()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    init(store: TodoStore? = nil, assistant: (any TodoAssistant)? = nil) {
        let url = URL.applicationSupportDirectory.appending(path: "aitodo.json")
        var startupError: String?
        if let store {
            self.store = store
        } else if let s = try? TodoStore(persistence: JSONFilePersistence(url: url)) {
            self.store = s
        } else {
            // Never overwrite a file we couldn't read: fall back to memory-only and say so.
            startupError = "Your saved todos couldn't be read, so changes won't be saved this session."
            self.store = try! TodoStore(persistence: InMemoryPersistence())
        }
        self.assistant = assistant ?? makeAssistant()
        aiEnabled = UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? true
        remindersEnabled = UserDefaults.standard.bool(forKey: "remindersEnabled")
        storageError = startupError
        self.store.onChange = { [weak self] in self?.storeChanged() }
        self.store.onError = { [weak self] _ in self?.storageError = "Couldn't save your todos. Free up storage space." }
        items = self.store.all
        Task { await loadBrief(force: false) }
        scheduleReminders()
    }

    // MARK: Derived
    var now: Date { store.now }
    var aiAvailable: Bool { aiEnabled && assistant.availability == .available }
    var insights: [Insight] { Proactive.insights(items, now: now, calendar: store.calendar) }
    var hasContent: Bool { !insights.isEmpty || !brief.message.isEmpty || (aiAvailable && !openItems.isEmpty) }
    private var openItems: [Todo] { items.filter(\.isOpen) }

    var sections: [TodoSection] {
        let now = self.now, cal = store.calendar
        let open = openItems
        func rank(_ a: Todo, _ b: Todo) -> Bool {
            if a.priority != b.priority { return a.priority > b.priority }
            return (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
        }
        let overdue = open.filter { Dates.isOverdue($0, now: now, calendar: cal) }.sorted(by: rank)
        let today = open.filter { Dates.isToday($0, now: now, calendar: cal) }.sorted(by: rank)
        let upcoming = open.filter { t in t.due != nil && !Dates.isOverdue(t, now: now, calendar: cal) && !Dates.isToday(t, now: now, calendar: cal) }
            .sorted { ($0.due ?? .distantFuture) != ($1.due ?? .distantFuture) ? ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) : $0.priority > $1.priority }
        let anytime = open.filter { $0.due == nil }.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.created > $1.created }
        return [
            TodoSection(title: "Overdue", isOverdue: true, todos: overdue),
            TodoSection(title: "Today", todos: today),
            TodoSection(title: "Upcoming", todos: upcoming),
            TodoSection(title: "Anytime", todos: anytime),
        ].filter { !$0.todos.isEmpty }
    }

    var recentlyDone: [Todo] {
        Array(items.filter { $0.done != nil && $0.deleted == nil }.sorted { $0.done! > $1.done! }.prefix(15))
    }

    var hasAnyTodos: Bool { !items.isEmpty }

    // MARK: Input
    /// Called on every keystroke: live preview + recall from memory.
    func inputChanged() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { preview = nil; recall = []; priorHint = nil; return }
        let p = TodoParser.parse(text, now: now, calendar: store.calendar)
        preview = p
        recall = store.recall(text, limit: 4)
        if let prior = store.findPrior(p.title), !prior.tags.isEmpty || prior.priority > 0 || !prior.note.isEmpty { priorHint = prior } else { priorHint = nil }
    }

    func submit() {
        let text = input
        switch store.add(text) {
        case .empty:
            return
        case .duplicate(let t):
            flash(t.id)
            showToast("Already on your list.")
        case .added(let t, let inherited, let prior):
            input = ""
            inputChanged()
            flash(t.id)
            feedbackTick += 1
            if let prior, !inherited.isEmpty {
                showToast("Added — reused \(inherited.joined(separator: ", ")) from “\(prior.title)”")
            } else {
                showToast("Added")
            }
            if aiAvailable { Task { await refine(t, original: text) } }
        }
    }

    private func refine(_ t: Todo, original: String) async {
        let memory = store.recall(t.title, limit: 5, excluding: t.id).map(\.todo)
        guard let suggestion = await assistant.refine(text: original, now: now, memory: memory, calendar: store.calendar) else { return }
        // Applied only if the user hasn't touched the todo meanwhile, and only to empty fields.
        if let updated = store.apply(suggestion, to: t.id, ifUnchangedSince: t.updated) {
            showToast("✨ Refined “\(updated.title)”")
        }
    }

    // MARK: Todo actions
    func complete(_ id: UUID) {
        guard let r = store.complete(id) else { return }
        feedbackTick += 1
        let msg = r.rolled ? "Done — next one \(Dates.formatDue(r.todo.due!, allDay: r.todo.allDay, now: now, calendar: store.calendar).lowercased())" : "Done"
        showToast(msg, actionLabel: "Undo") { [store] in store.replace(r.before) }
    }

    func uncomplete(_ id: UUID) { store.uncomplete(id) }

    func delete(_ id: UUID) {
        guard let snapshot = store.get(id) else { return }
        store.remove(id)
        showToast("Deleted — it stays in memory", actionLabel: "Undo") { [store] in store.replace(snapshot) }
    }

    func readd(_ id: UUID) {
        let wasDeleted = store.get(id)?.deleted != nil
        guard let t = store.readd(id) else { return }
        input = ""; inputChanged()
        flash(t.id)
        showToast(wasDeleted ? "Restored" : "Added again")
    }

    func show(_ id: UUID) { input = ""; inputChanged(); flash(id) }

    func save(_ edited: Todo) {
        store.update(edited.id) { t in
            t.title = edited.title; t.note = edited.note; t.due = edited.due; t.allDay = edited.allDay
            t.repeatRule = edited.repeatRule; t.priority = edited.priority; t.tags = edited.tags; t.notified = nil
        }
    }

    func run(_ action: InsightAction, on insight: Insight) {
        let today = store.calendar.startOfDay(for: now)
        switch action {
        case .rescheduleToday:
            for id in insight.todoIDs { store.update(id) { $0.due = today; $0.allDay = true } }
        case .scheduleToday:
            if let id = insight.todoIDs.first { store.update(id) { $0.due = today; $0.allDay = true } }
        case .drop:
            if let id = insight.todoIDs.first { delete(id) }
        case .addHabit:
            if let title = insight.title, case .added(let t, _, _) = store.add(title) {
                store.update(t.id) { $0.due = today; $0.allDay = true }
                flash(t.id)
                showToast("Added to today")
            }
        }
    }

    // MARK: AI brief
    func loadBrief(force: Bool) async {
        guard aiAvailable, !openItems.isEmpty else { return }
        let key = Dates.dayKey(now, calendar: store.calendar)
        if !force, defaults.string(forKey: "briefDay") == key, let msg = defaults.string(forKey: "briefMessage") {
            let ids = (defaults.stringArray(forKey: "briefFocus") ?? []).compactMap(UUID.init(uuidString:))
            brief = BriefState(message: msg, focus: ids)
            return
        }
        brief.loading = true
        defer { brief.loading = false }
        guard let r = await assistant.brief(todos: items, now: now, calendar: store.calendar) else { return }
        brief = BriefState(message: r.message, focus: r.focus)
        defaults.set(key, forKey: "briefDay")
        defaults.set(r.message, forKey: "briefMessage")
        defaults.set(r.focus.map(\.uuidString), forKey: "briefFocus")
    }

    // MARK: Settings
    func setAIEnabled(_ on: Bool) {
        aiEnabled = on
        defaults.set(on, forKey: "aiEnabled")
        if on { Task { await loadBrief(force: false) } } else { brief = BriefState() }
    }

    /// Returns false if the user denied notification permission.
    @discardableResult
    func setRemindersEnabled(_ on: Bool) async -> Bool {
        if on {
            guard await reminders.requestAuthorization() else {
                remindersEnabled = false; defaults.set(false, forKey: "remindersEnabled"); return false
            }
        } else {
            reminders.cancelAll()
        }
        remindersEnabled = on
        defaults.set(on, forKey: "remindersEnabled")
        scheduleReminders()
        return true
    }

    func exportFile() -> URL? {
        guard let data = try? store.exportData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "aitodo-\(Dates.dayKey(now, calendar: store.calendar)).json")
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { showToast("Imported \(try store.importData(Data(contentsOf: url))) todos") }
        catch { showToast("That file isn't an AI Todo export.") }
    }

    var stats: String {
        "\(items.count) remembered · \(items.filter { $0.done != nil }.count) done · stored on this device"
    }

    func didBecomeActive() {
        items = store.all   // also re-evaluates "today" after midnight
        scheduleReminders()
        Task { await loadBrief(force: false) }
    }

    // MARK: Internals
    private func storeChanged() {
        items = store.all
        inputChanged()
        scheduleReminders()
    }

    private func scheduleReminders() {
        guard remindersEnabled else { return }
        rescheduleTask?.cancel()
        rescheduleTask = Task { [items, store, reminders] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await reminders.reschedule(items, now: store.now, calendar: store.calendar)
        }
    }

    private func flash(_ id: UUID) {
        flashID = id
        Task { try? await Task.sleep(for: .seconds(1.6)); if flashID == id { flashID = nil } }
    }

    func showToast(_ message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        let t = Toast(message: message, actionLabel: actionLabel, action: action)
        toast = t
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(actionLabel == nil ? 3.5 : 6))
            if !Task.isCancelled, toast?.id == t.id { toast = nil }
        }
    }
}
