import SwiftUI
import AIToDoCore

struct EditView: View {
    let todo: Todo
    var onSave: (Todo) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var date: Date
    @State private var repeatChoice: String
    @State private var priority: Int
    @State private var tagText: String

    init(todo: Todo, onSave: @escaping (Todo) -> Void, onDelete: @escaping () -> Void) {
        self.todo = todo; self.onSave = onSave; self.onDelete = onDelete
        _title = State(initialValue: todo.title)
        _note = State(initialValue: todo.note)
        _hasDate = State(initialValue: todo.due != nil)
        _hasTime = State(initialValue: todo.due != nil && !todo.allDay)
        _date = State(initialValue: todo.due ?? Date())
        _repeatChoice = State(initialValue: todo.repeatRule == nil ? "none" : (RepeatPreset.matching(todo.repeatRule)?.rawValue ?? "custom"))
        _priority = State(initialValue: todo.priority)
        _tagText = State(initialValue: todo.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Todo", text: $title)
                    TextField("Note", text: $note, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Toggle("Date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Day", selection: $date, displayedComponents: .date)
                        Toggle("Time", isOn: $hasTime.animation())
                        if hasTime { DatePicker("At", selection: $date, displayedComponents: .hourAndMinute) }
                    }
                    Picker("Repeat", selection: $repeatChoice) {
                        Text("Never").tag("none")
                        ForEach(RepeatPreset.allCases) { Text($0.label).tag($0.rawValue) }
                        if todo.repeatRule != nil && RepeatPreset.matching(todo.repeatRule) == nil {
                            Text(Dates.describeRepeat(todo.repeatRule)).tag("custom")
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        Text("Normal").tag(0); Text("High").tag(1); Text("Urgent").tag(2)
                    }
                    TextField("Tags (home, errands)", text: $tagText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section { Text(history).font(.footnote).foregroundStyle(.secondary) }
                Section {
                    Button("Delete", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
        .presentationDetents([.large])
    }

    private var history: String {
        var s = "Written " + todo.created.formatted(date: .abbreviated, time: .omitted)
        let n = todo.completionDates.count
        if n > 0, let last = todo.completionDates.last { s += " · completed \(n)×, last \(last.formatted(date: .abbreviated, time: .omitted))" }
        return s
    }

    private func save() {
        var t = todo
        t.title = title.trimmingCharacters(in: .whitespaces)
        t.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current
        // Both pickers edit the same Date (the date picker keeps its time, the time picker keeps its day).
        t.due = hasDate ? (hasTime ? date : cal.startOfDay(for: date)) : nil
        t.allDay = !(hasDate && hasTime)
        switch repeatChoice {
        case "none": t.repeatRule = nil
        case "custom": break
        default: t.repeatRule = RepeatPreset(rawValue: repeatChoice)?.rule
        }
        t.priority = priority
        t.tags = Array(Set(tagText.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#")) }.filter { !$0.isEmpty })).sorted().prefix(8).map { $0 }
        onSave(t)
        dismiss()
    }
}
